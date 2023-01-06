#!/bin/sh -l

# https://linuxhint.com/set-command-bash/
set -e
set -u

SRC_DIR="${1}"
DEST_DIR="${2}"
DEST_GH_USERNAME="${3}"
DEST_REPO_NAME="${4}"
USER_EMAIL="${5}"
TARGET_BRANCH="${6}"
COMMIT_MSG="${7}"

# https://www.gnu.org/software/bash/manual/bash.html#Bash-Conditional-Expressions
if [ -n "${SSH_DEPLOY_KEY:=}" ]
then
	echo "::Using SSH_DEPLOY_KEY"

	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh , thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" > "$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H "github.com" > "$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@github.com:$DEST_GH_USERNAME/$DEST_REPO_NAME.git"
else
	echo "::ERR: SSH_DEPLOY_KEY not provided"
	exit 1
fi

CLONE_DIR=$(mktemp -d)

echo ":: Clone dest repo $DEST_REPO_NAME"
# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$DEST_GH_USERNAME"

{
	git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
} || {
	echo ":: ERR: Could not clone the destination repository. Command:"
	echo ":: ERR: git clone --single-branch --branch $TARGET_BRANCH $GIT_CMD_REPOSITORY $CLONE_DIR"
	exit 1

}
ls -la "$CLONE_DIR"


# https://devcoops.com/install-rsync-on-alpine-linux/
rsync --version

# https://unix.stackexchange.com/questions/149965/how-to-copy-merge-two-directories
# https://unix.stackexchange.com/questions/88788/merge-folders-and-replace-files-using-cli
echo ":: Copy and merge"
{
	rsync -avh --progress "$SRC_DIR/" "$CLONE_DIR/$DEST_DIR"
} || {
	echo ":: ERR: Could not merge target and dest folders. Command:"
	echo ":: ERR: rsync -avhu --progress $GITHUB_WORKSPACE/$SRC_DIR/ ~$CLONE_DIR/$DEST_DIR"
	exit 1
}

cd "$CLONE_DIR"

ORIGIN_COMMIT="https://github.com/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
COMMIT_MSG="${COMMIT_MSG/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
COMMIT_MSG="${COMMIT_MSG/\$GITHUB_REF/$GITHUB_REF}"

git config --global --add safe.directory "$CLONE_DIR"

echo ":: Add git commit"
git add .

echo ":: git status"
git status

echo ":: git diff-index"
# git diff-index : to avoid doing the git commit failing if there are no changes to be commit
git diff-index --quiet HEAD || git commit --message "$COMMIT_MSG"

echo ":: Pushing git commit"
# --set-upstream: sets de branch when pushing to a branch that does not exist
git push "$GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"