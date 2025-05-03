# dev-tools
Repo to host dev tools useful to automate build, git repo and docker operations

## deploy.sh

A comprehensive deployment automation script that handles Git operations, Docker builds, and security scanning.

### Features

- **Version Management**
  - Detects current version from git tags and commit messages
  - Supports four-part versioning (major.minor.patch.subpatch)
  - Interactive version increment selection
  - Automatically suggests next version based on increment type

- **Git Operations**
  - Checks for uncommitted changes
  - Generates smart commit messages based on changed files
  - Commits and pushes changes using credentials from .deployenv
  - Skips git operations if no changes detected

- **Docker Operations**
  - Uses Docker BuildKit for efficient, modern builds
  - Builds Docker image with specified version
  - Tags image with both version and 'latest'
  - Pushes images to registry using credentials from .deployenv

- **Security**
  - Advanced sensitive data detection with pattern recognition
  - Trufflehog integration for superior secret detection
  - Alternative deep scanning when Trufflehog is unavailable
  - Displays line numbers for pinpointing sensitive data
  - Checks for sensitive files and credentials before commit
  - Recommends adding sensitive files to .gitignore

### Setup Instructions

1. **Copy the Script**
   - Add `deploy.sh` to the root of your project
   - Make it executable: `chmod +x deploy.sh`

2. **Create Environment File**
   - Create a `.deployenv` file in the same directory with the following variables:
     ```
     DOCKER_USERNAME=your_docker_username
     DOCKER_PASSWORD=your_docker_password
     DOCKER_REPO=your_docker_repository
     GIT_USERNAME=your_git_username
     GIT_PASSWORD=your_git_password
     GIT_REPO=your_git_repository
     ```
   - Add `.deployenv` to your `.gitignore`

3. **Docker Setup**
   - Ensure you have a `Dockerfile` in your project root
   - The script will build using this Dockerfile

4. **Trufflehog (Optional but Recommended)**
   - Install Trufflehog for enhanced security scanning:
     ```
     pip install trufflehog
     ```
   - If not installed, the script will use its built-in scanning capabilities

### Usage

Run the script from your project root:

```bash
./deploy.sh
```

The script will:
1. Check for uncommitted changes
2. Scan for sensitive data
3. Prompt for version increment type (major/minor/patch/subpatch)
4. Generate commit message (or ask for one)
5. Perform git operations (commit, push)
6. Build and push Docker images

### Security Considerations

- **Credentials**: Store all credentials in the `.deployenv` file, not in the script
- **Scanning**: The script performs thorough scanning for sensitive data before commits
- **Gitignore**: Make sure `.deployenv` is in your `.gitignore`
- **Sensitive Files**: Common sensitive files like `service-account.json` will be detected

### Requirements

- Git
- Docker
- Bash
- Trufflehog (optional)

### Adding to Your Project

Simply copy both the `deploy.sh` script and create a `.deployenv` file in your project root. The script will handle version management, git operations, Docker builds, and security scanning automatically.
