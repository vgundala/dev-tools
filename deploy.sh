#!/bin/bash

# =====================================================
# Copyright (c) 2024 Vinay Gundala <vg@ivdata.dev>
# Copyright (c) 2024 Infoverse Data LLC
# All rights reserved.
# =====================================================
# =====================================================
# Thanks to friendly AI bot to speed up the development of this script
# =====================================================
# Deployment Script Overview
# =====================================================
# This script automates the deployment process from local dev to docker registry and git repository with the following features:
#
# 1. Version Management:
#    - Detects current version from git tags and commit messages
#    - Supports four-part versioning (major.minor.patch.subpatch)
#    - Interactive version increment selection (major/minor/patch/subpatch)
#    - Automatically suggests next version based on increment type
#
# 2. Git Operations:
#    - Checks for uncommitted changes
#    - Prompts for commit message with default
#    - Commits and pushes changes using credentials from .deployenv
#    - Skips git operations if no changes detected
#    - Checks for sensitive files and credentials before commit
#    - Generates smart commit messages based on changed files
#
# 3. Docker Operations:
#    - Builds Docker image with specified version
#    - Tags image with both version and 'latest'
#    - Pushes images to registry using credentials from .deployenv
#
# 4. Interactive Prompts:
#    - Version increment type selection
#    - Docker version confirmation
#    - Commit message input
#    - Confirmation for git operations
#    - Confirmation for Docker operations
#
# 5. Error Handling:
#    - Validates environment variables
#    - Checks for .deployenv file
#    - Verifies git and Docker operations
#    - Provides clear error messages
#
# 6. Security:
#    - Uses credentials from .deployenv file
#    - Supports secure git and Docker authentication
#    - Recommends adding .deployenv to .gitignore
#    - Scans for sensitive files and credentials before commit
#
# =====================================================
# Configuration Instructions
# =====================================================
# Create a .deployenv file in the same directory as this script
# with the following environment variables:
#
# DOCKER_USERNAME=your_docker_username
# DOCKER_PASSWORD=your_docker_password
# DOCKER_REPO=your_docker_repository
# GIT_USERNAME=your_git_username
# GIT_PASSWORD=your_git_password
# GIT_REPO=your_git_repository
#
#
# Note: Make sure to add .deployenv to .gitignore to keep credentials secure
# =====================================================

# Source environment variables
if [ ! -f .deployenv ]; then
    echo "Error: .deployenv file not found"
    exit 1
fi

# Source the environment file
set -a
source .deployenv
set +a

# Verify required environment variables
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_REPO" ]; then
    echo "Error: DOCKER_USERNAME, DOCKER_PASSWORD, or DOCKER_REPO not set in .deployenv"
    exit 1
fi

if [ -z "$GIT_USERNAME" ] || [ -z "$GIT_PASSWORD" ] || [ -z "$GIT_REPO" ]; then
    echo "Error: GIT_USERNAME, GIT_PASSWORD, or GIT_REPO not set in .deployenv"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get user confirmation
get_confirmation() {
    local prompt=$1
    while true; do
        echo -e "${BLUE}[INPUT]${NC} $prompt (y/n): \c"
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to get version increment type
get_version_increment_type() {
    local current_version=$1
    local increment_type=$2
    case $increment_type in
        major|minor|patch|subpatch) echo "$increment_type"; return 0;;
        *) echo "Please enter one of: major, minor, patch, subpatch"; return 1;;
    esac
}

# Function to get the last version number from git tags
get_last_version() {
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null)
    if [ -z "$last_tag" ]; then
        echo "0.0.0.0"
    else
        echo "$last_tag"
    fi
}

# Function to get version from commit messages
get_version_from_commits() {
    # Get the last 10 commit messages and look for version numbers
    local version=$(git log -n 10 --pretty=format:"%s" | grep -oP 'v?\d+\.\d+\.\d+\.\d+' | head -n 1)
    if [ -z "$version" ]; then
        echo "0.0.0.0"
    else
        # Remove 'v' prefix if present
        echo "${version#v}"
    fi
}

# Function to increment version number
increment_version() {
    local version=$1
    local part=$2  # major, minor, patch, or subpatch
    
    IFS='.' read -r major minor patch subpatch <<< "$version"
    case "$part" in
        major) major=$((major + 1)); minor=0; patch=0; subpatch=0 ;;
        minor) minor=$((minor + 1)); patch=0; subpatch=0 ;;
        patch) patch=$((patch + 1)); subpatch=0 ;;
        subpatch) subpatch=$((subpatch + 1)) ;;
    esac
    echo "$major.$minor.$patch.$subpatch"
}

# Function to check for sensitive files and credentials
check_sensitive_files() {
    local sensitive_files=(
        ".env"
        ".deployenv"
        "credentials.json"
        "config.json"
        "secrets.json"
        "*.pem"
        "*.key"
        "*.crt"
        "id_rsa"
        "id_rsa.pub"
        "*.p12"
        "*.pfx"
    )
    
    local sensitive_patterns=(
        "password"
        "secret"
        "key"
        "token"
        "credential"
        "api_key"
        "access_key"
        "secret_key"
    )
    
    print_status "Checking for sensitive files and credentials..."
    
    # Check for sensitive files
    for pattern in "${sensitive_files[@]}"; do
        # Find files matching pattern, excluding .git directory
        found_files=$(find . -name "$pattern" | grep -v "^./.git/")
        if [ -n "$found_files" ]; then
            # Filter out files that are in .gitignore
            non_ignored_files=""
            for file in $found_files; do
                relative_path=${file#./}
                if ! git check-ignore -q "$relative_path"; then
                    non_ignored_files+="$file"$'\n'
                fi
            done
            
            if [ -n "$non_ignored_files" ]; then
                print_warning "Found sensitive file(s) matching pattern: $pattern"
                echo "Files found:"
                echo "$non_ignored_files"
                
                for file in $non_ignored_files; do
                    relative_path=${file#./}
                    if ! get_confirmation "Do you want to add $relative_path to .gitignore?"; then
                        print_error "Commit cancelled due to sensitive files not being ignored"
                        exit 1
                    else
                        echo "$relative_path" >> .gitignore
                        print_status "Added $relative_path to .gitignore"
                    fi
                done
                
                if ! get_confirmation "Do you want to continue despite finding sensitive files?"; then
                    print_error "Commit cancelled due to sensitive files"
                    exit 1
                fi
            fi
        fi
    done
    
    # Check for sensitive patterns in files
    for pattern in "${sensitive_patterns[@]}"; do
        # First get list of all non-ignored files
        non_ignored_files=$(git ls-files --others --exclude-standard)
        
        if [ -n "$non_ignored_files" ]; then
            # Search for patterns only in non-ignored files
            found_matches=$(grep -r --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=venv -i "$pattern" $non_ignored_files 2>/dev/null)
            
            if [ -n "$found_matches" ]; then
                print_warning "Found potential credentials matching pattern: $pattern"
                echo "Matches found in:"
                echo "$found_matches" | cut -d: -f1 | sort -u
                
                for file in $(echo "$found_matches" | cut -d: -f1 | sort -u); do
                    relative_path=${file#./}
                    if ! get_confirmation "Do you want to add $relative_path to .gitignore?"; then
                        print_error "Commit cancelled due to sensitive content not being ignored"
                        exit 1
                    else
                        echo "$relative_path" >> .gitignore
                        print_status "Added $relative_path to .gitignore"
                    fi
                done
                
                if ! get_confirmation "Do you want to continue despite finding potential credentials?"; then
                    print_error "Commit cancelled due to potential credentials"
                    exit 1
                fi
            fi
        fi
    done
}

# Get versions from different sources
TAG_VERSION=$(get_last_version)
COMMIT_VERSION=$(get_version_from_commits)

# Use the higher version between tag and commit
if [ "$(printf '%s\n' "$TAG_VERSION" "$COMMIT_VERSION" | sort -V | tail -n1)" = "$TAG_VERSION" ]; then
    LAST_VERSION=$TAG_VERSION
else
    LAST_VERSION=$COMMIT_VERSION
fi

# Check for uncommitted changes
print_status "Checking for uncommitted changes..."
if git diff-index --quiet HEAD --; then
    print_warning "No uncommitted changes found. Skipping git operations."
    NEXT_VERSION=$LAST_VERSION
    DOCKER_TAG=$LAST_VERSION
    print_status "Using current version for Docker operations: $DOCKER_TAG"
else
    # Get version increment type
    echo ""
    print_status "Current version: $LAST_VERSION"
    while true; do
        echo -e "${BLUE}[INPUT]${NC} Incrementing major or minor or patch or subpatch?"
        read -r increment_type
        if get_version_increment_type "$LAST_VERSION" "$increment_type"; then
            INCREMENT_TYPE=$increment_type
            break
        fi
    done

    # Suggest next version
    NEXT_VERSION=$(increment_version "$LAST_VERSION" "$INCREMENT_TYPE")

    # Get Docker version
    print_status "Please provide the following information:"
    print_status "Last version from tags: $TAG_VERSION"
    print_status "Last version from commits: $COMMIT_VERSION"
    print_status "Using version: $LAST_VERSION"
    print_status "Suggested next version: $NEXT_VERSION"
    echo -e "${BLUE}[INPUT]${NC} Enter docker image version number (default: $NEXT_VERSION): \c"
    read -r DOCKER_TAG
    DOCKER_TAG=${DOCKER_TAG:-$NEXT_VERSION}

    # Check for sensitive files before proceeding
    check_sensitive_files
    
    # Function to generate smart commit message
    generate_commit_message() {
        # Get both staged and unstaged changes
        local changed_files=$(git status --porcelain | awk '{print $2}')
        local message="Update to version $NEXT_VERSION\n\nChanged files:\n"
        
        # Group files by type
        local python_files=$(echo "$changed_files" | grep -E '\.py$')
        local config_files=$(echo "$changed_files" | grep -E '\.(json|yaml|yml|toml|ini|cfg)$')
        local shell_files=$(echo "$changed_files" | grep -E '\.(sh|bash)$')
        local other_files=$(echo "$changed_files" | grep -vE '\.(py|json|yaml|yml|toml|ini|cfg|sh|bash)$')
        
        if [ -n "$python_files" ]; then
            message+="\nPython files:\n$python_files\n"
        fi
        
        if [ -n "$config_files" ]; then
            message+="\nConfiguration files:\n$config_files\n"
        fi
        
        if [ -n "$shell_files" ]; then
            message+="\nShell scripts:\n$shell_files\n"
        fi
        
        if [ -n "$other_files" ]; then
            message+="\nOther files:\n$other_files\n"
        fi
        
        # Add git status summary
        message+="\nGit status summary:\n"
        message+="$(git status --porcelain)\n"
        
        echo -e "$message"
    }

    # Get commit message
    print_status "There are pending commits"
    DEFAULT_COMMIT_MESSAGE=$(generate_commit_message)
    echo -e "${BLUE}[INPUT]${NC} Enter commit message (default shown below):\n$DEFAULT_COMMIT_MESSAGE\n"
    read -r COMMIT_MESSAGE
    COMMIT_MESSAGE="${NEXT_VERSION} - ${COMMIT_MESSAGE:-$DEFAULT_COMMIT_MESSAGE}"
    
    # Ask for confirmation before committing
    if ! get_confirmation "Do you want to proceed with the commit?"; then
        print_status "Commit cancelled by user"
        exit 0
    fi
    
    # Git operations
    print_status "Starting git operations..."
    git add --all
    git commit -m "$COMMIT_MESSAGE"
    if [ $? -ne 0 ]; then
        print_error "Git commit failed"
        exit 1
    fi

    # Configure git credentials
    print_status "Configuring git credentials..."
    git remote set-url origin "https://${GIT_USERNAME}:${GIT_PASSWORD}@${GIT_REPO#https://}"
    if [ $? -ne 0 ]; then
        print_error "Failed to set git remote URL"
        exit 1
    fi

    git push origin main
    if [ $? -ne 0 ]; then
        print_error "Git push failed"
        exit 1
    fi
    print_status "Git operations completed successfully"
fi

# Ask for confirmation before Docker operations
if ! get_confirmation "Do you want to proceed with Docker build and push?"; then
    print_status "Docker operations cancelled by user"
    if [ "$NEXT_VERSION" != "$LAST_VERSION" ]; then
        print_status "Git operations completed successfully"
    fi
    exit 0
fi

# Docker operations
print_status "Starting Docker operations..."
print_status "Logging into Docker registry..."
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin "$DOCKER_REPO"
if [ $? -ne 0 ]; then
    print_error "Docker login failed"
    exit 1
fi

# Build the Docker image
print_status "Building Docker image..."
docker build -t "$DOCKER_REPO:$DOCKER_TAG" .
if [ $? -ne 0 ]; then
    print_error "Docker build failed"
    exit 1
fi

# Push the Docker image
print_status "Pushing Docker image..."
docker push "$DOCKER_REPO:$DOCKER_TAG"
if [ $? -ne 0 ]; then
    print_error "Docker push failed"
    exit 1
fi

# Also push as latest
print_status "Tagging and pushing as latest..."
docker tag "$DOCKER_REPO:$DOCKER_TAG" "$DOCKER_REPO:latest"
docker push "$DOCKER_REPO:latest"
if [ $? -ne 0 ]; then
    print_error "Docker push latest failed"
    exit 1
fi

print_status "Docker operations completed successfully"
print_status "Deployment completed successfully!" 