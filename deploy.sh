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
#    - Uses Docker BuildKit for efficient, modern builds
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
#    - Advanced sensitive data detection with pattern recognition
#    - Trufflehog integration for superior secret detection
#    - Alternative deep scanning when Trufflehog is unavailable
#    - Displays line numbers for pinpointing sensitive data
#    - Uses credentials from .deployenv file
#    - Supports secure git and Docker authentication
#    - Recommends adding .deployenv to .gitignore
#    - Scans for sensitive files and credentials before commit
#    - Excludes itself (deploy.sh) from sensitive data scanning
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
    local response=""
    
    echo -e "${BLUE}[INPUT]${NC} $prompt (y/n): \c"
    read -r response
    
    while [[ ! "$response" =~ ^[YyNn]$ ]]; do
        echo "Please answer yes or no."
        echo -e "${BLUE}[INPUT]${NC} $prompt (y/n): \c"
        read -r response
    done
    
    [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
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
        "service_account.json"
        "service-account.json"
        "*.pem"
        "*.key"
        "*.crt"
        "id_rsa"
        "id_rsa.pub"
        "*.p12"
        "*.pfx"
    )
    
    # More sophisticated regex patterns for sensitive data
    local sensitive_patterns=(
        # AWS keys
        "[A-Z0-9]{20}"
        "AKIA[0-9A-Z]{16}"
        # API keys and tokens (common formats) - improved to reduce false positives
        "(?<![\w._-])[a-zA-Z0-9_-]{32,45}(?![\w._-])"
        # Private keys
        "-----BEGIN.*PRIVATE KEY-----"
        # JWT tokens
        "eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"
        # Database connection strings
        "postgres://.*:.*@.*:[0-9]{4,5}/.*"
        "mysql://.*:.*@.*:[0-9]{4,5}/.*"
        "mongodb://.*:.*@.*:[0-9]{4,5}/.*"
        # Authorization headers
        "Authorization: Bearer [a-zA-Z0-9_.-]+"
        "Authorization: Basic [a-zA-Z0-9+/=]+"
        # Generic passwords and secrets
        "password['\"]?\s*[:=]\s*['\"][^'\"]{8,}['\"]"
        "secret['\"]?\s*[:=]\s*['\"][^'\"]{8,}['\"]"
        "key['\"]?\s*[:=]\s*['\"][^'\"]{16,}['\"]"
    )
    
    # Additional entropy-based patterns for the manual scan
    local entropy_patterns=(
        # High entropy strings (likely keys, tokens, passwords)
        "[a-zA-Z0-9+/]{32,}"
        "[a-zA-Z0-9]{32,}"
        # GitHub tokens and OAuth patterns
        "gh[pousr]_[A-Za-z0-9_]{20,}"
        "gho_[A-Za-z0-9_]{36,}"
        # Google API keys
        "AIza[0-9A-Za-z_-]{35}"
        # Stripe API keys
        "sk_live_[0-9a-zA-Z]{24}"
        "pk_live_[0-9a-zA-Z]{24}"
        # AWS Account ID
        "[0-9]{12}"
        # Generic hex keys
        "[0-9a-fA-F]{32,}"
    )
    
    # Script name to exclude from checks (the current script)
    local script_name=$(basename "$0")
    
    print_status "Checking for sensitive files and credentials..."
    print_status "Excluding the current script ($script_name) from checks..."
    
    # Check if trufflehog is installed
    if command -v trufflehog &> /dev/null; then
        print_status "Running TruffleHog to scan for secrets..."
        # Exclude the current script from trufflehog scanning
        trufflehog_output=$(trufflehog filesystem --no-update --only-verified --exclude "$script_name" . 2>/dev/null || echo "")
        
        if [ -n "$trufflehog_output" ]; then
            print_warning "TruffleHog found potential secrets:"
            echo "$trufflehog_output"
            
            if ! get_confirmation "Do you want to continue with the build despite TruffleHog finding secrets?"; then
                print_error "Build cancelled due to secrets found by TruffleHog"
                exit 1
            else
                print_warning "Continuing despite TruffleHog findings"
            fi
        else
            print_status "TruffleHog scan completed - no secrets found."
        fi
    else
        print_warning "TruffleHog not installed. Using alternative deep scanning method."
        
        # Run alternative deep scan using native tools
        print_status "Running alternative deep scan for secrets..."
        
        # Get all text files that aren't ignored by git, excluding the current script
        text_files=$(git ls-files --cached --others --exclude-standard | grep -v "\.jpg$\|\.png$\|\.gif$\|\.zip$\|\.tar$\|\.gz$\|\.pdf$\|$script_name$")
        
        # Create a temporary file to store scan results
        scan_results=$(mktemp)
        
        # Function to check file for entropy patterns
        scan_file_for_patterns() {
            local file=$1
            local patterns=("${!2}")
            
            # Skip if this is the current script
            if [[ "$(basename "$file")" == "$script_name" ]]; then
                return
            fi
            
            for pattern in "${patterns[@]}"; do
                # Use grep with line numbers (-n flag)
                matches=$(grep -n -E "$pattern" "$file" 2>/dev/null)
                if [ -n "$matches" ]; then
                    echo "File: $file" >> "$scan_results"
                    echo "Pattern: $pattern" >> "$scan_results"
                    echo "Match (line:content):" >> "$scan_results"
                    echo "$matches" >> "$scan_results"
                    echo "---" >> "$scan_results"
                fi
            done
        }
        
        # Process each file
        for file in $text_files; do
            # Skip binary files and the current script
            if file "$file" | grep -q "binary" || [[ "$(basename "$file")" == "$script_name" ]]; then
                continue
            fi
            
            # Check for sensitive patterns
            scan_file_for_patterns "$file" sensitive_patterns[@]
            
            # Check for entropy patterns
            scan_file_for_patterns "$file" entropy_patterns[@]
            
            # Check for Base64 encoded secrets (lines that look like base64 and are long enough)
            base64_matches=$(grep -n -E "^[A-Za-z0-9+/]{40,}={0,2}$" "$file" 2>/dev/null)
            if [ -n "$base64_matches" ]; then
                echo "File: $file" >> "$scan_results"
                echo "Pattern: Base64 encoded secret" >> "$scan_results"
                echo "Match (line:content):" >> "$scan_results"
                echo "$base64_matches" >> "$scan_results"
                echo "---" >> "$scan_results"
            fi
        done
        
        # Check if we found any results
        if [ -s "$scan_results" ]; then
            print_warning "Alternative scan found potential secrets:"
            cat "$scan_results"
            
            if ! get_confirmation "Do you want to continue with the build despite finding potential secrets?"; then
                rm "$scan_results"
                print_error "Build cancelled due to potential secrets found"
                exit 1
            else
                print_warning "Continuing despite finding potential secrets"
            fi
        else
            print_status "Alternative scan completed - no secrets found."
        fi
        
        # Clean up temporary file
        rm "$scan_results"
    fi
    
    # Check for sensitive files
    for pattern in "${sensitive_files[@]}"; do
        # Find files matching pattern, excluding .git directory and the current script
        found_files=$(find . -name "$pattern" | grep -v "^./.git/" | grep -v "/$script_name$")
        if [ -n "$found_files" ]; then
            # Filter out files that are in .gitignore
            non_ignored_files=""
            for file in $found_files; do
                relative_path=${file#./}
                # Skip the current script
                if [[ "$(basename "$relative_path")" == "$script_name" ]]; then
                    continue
                fi
                
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
                    # Skip if this is the current script
                    if [[ "$(basename "$relative_path")" == "$script_name" ]]; then
                        continue
                    fi
                    
                    if ! get_confirmation "Do you want to add $relative_path to .gitignore?"; then
                        if ! get_confirmation "Do you want to continue with the build despite not ignoring this sensitive file?"; then
                            print_error "Build cancelled due to sensitive files not being ignored"
                            exit 1
                        else
                            print_warning "Continuing with sensitive file $relative_path not ignored"
                        fi
                    else
                        echo "$relative_path" >> .gitignore
                        print_status "Added $relative_path to .gitignore"
                    fi
                done
            fi
        fi
    done
    
    # Check for sensitive patterns in files using advanced regex
    for pattern in "${sensitive_patterns[@]}"; do
        # Limit to non-ignored files, excluding binaries, common non-text files, and the current script
        non_ignored_files=$(git ls-files --cached --others --exclude-standard | grep -v "\.jpg$\|\.png$\|\.gif$\|\.zip$\|\.tar$\|\.gz$\|$script_name$")
        
        if [ -n "$non_ignored_files" ]; then
            # Use grep with regex pattern (extended regex) and line numbers (-n flag)
            found_matches=$(grep -n -E -r --include="$(echo $non_ignored_files | tr ' ' '\n' | paste -sd ',' -)" "$pattern" . 2>/dev/null || echo "")
            
            if [ -n "$found_matches" ]; then
                # Filter out matches from the current script
                filtered_matches=$(echo "$found_matches" | grep -v "^./$script_name:")
                
                if [ -n "$filtered_matches" ]; then
                    print_warning "Found potential sensitive data matching pattern: $pattern"
                    echo "Matches found in (file:line:content):"
                    echo "$filtered_matches"
                    
                    for file in $(echo "$filtered_matches" | cut -d: -f1 | sort -u); do
                        relative_path=${file#./}
                        # Skip if this is the current script
                        if [[ "$(basename "$relative_path")" == "$script_name" ]]; then
                            continue
                        fi
                        
                        if ! get_confirmation "Do you want to add $relative_path to .gitignore?"; then
                            if ! get_confirmation "Do you want to continue with the build despite not ignoring this file with sensitive content?"; then
                                print_error "Build cancelled due to files with sensitive content not being ignored"
                                exit 1
                            else
                                print_warning "Continuing with file containing sensitive content $relative_path not ignored"
                            fi
                        else
                            echo "$relative_path" >> .gitignore
                            print_status "Added $relative_path to .gitignore"
                        fi
                    done
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

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# Build the Docker image
print_status "Building Docker image with BuildKit..."
docker build --progress=plain -t "$DOCKER_REPO:$DOCKER_TAG" .
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