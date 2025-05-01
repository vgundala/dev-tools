# dev-tools
Repo to host dev tools useful to automate build,git repo and docker operations
1. deploy.sh - Add this to the root your python projects along with .deployenv file to keep track of code changes, check for sensitive info before commits and pushing to remote; build docker images, push to package manager.
    * Commits and pushes the active branch
    * Dockerfile needed to build
    * Use tags to define package manager url in docker
