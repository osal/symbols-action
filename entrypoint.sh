#!/bin/bash

set -x

git version
gh --version
aws --version
jq --version

git fetch origin --depth=1 > /dev/null 2>&1

# check for deleted JSON files
DELETED=$(git diff --name-only --diff-filter=D origin/master)
if [ -n "$DELETED" ]; then
  echo Deleting files is forbidden
  echo These files were deleted:
  echo "$DELETED"
  gh pr review "$GITHUB_HEAD_REF" -r -b "Deleting files is forbidden\nDeleted: $DELETED"
  exit 1
fi

# check for renamed JSON files
RENAMED=$(git diff --name-only --diff-filter=R origin/master)
if [ -n "$RENAMED" ]; then
  echo Renaming files is forbidden
  echo These files were renamed:
  echo "$RENAMED"
  gh pr review "$GITHUB_HEAD_REF" -r -b "Renaming files is forbidden\nRenamed: $RENAMED"
  exit 1
fi

# check for added JSON files
ADDED=$(git diff --name-only --diff-filter=A origin/master)
if [ -n "$ADDED" ]; then
  echo Adding files is forbidden
  echo These files were added:
  echo "$ADDED"
  gh pr review "$GITHUB_HEAD_REF" -r -b "Adding files is forbidden\nAdded: $ADDED"
  exit 1
fi

# validate modified files
MODIFIED=$(git diff --name-only origin/master | grep ".json$")
if [ -z "$MODIFIED" ]; then
  echo No symbol info files were modified
  gh pr review "$GITHUB_HEAD_REF" -r -b "No symbol info files (JSON) were modified"
  exit 1
fi

# save new versions
for F in $MODIFIED; do cp "$F" "$F.new"; done

# save old versions
git checkout -b old origin/master
for F in $MODIFIED; do cp "$F" "$F.old"; done

# download inspect tool
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID_INSPECT AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY_INSPECT \
aws s3 cp s3://tradingview-customers-inspect/inspect_r4.4 ./inspect && chmod +x ./inspect
./inspect version

# check files
FAILED=false
for F in $MODIFIED; do
  echo Checking "$F"
  ./inspect symfile --old="$F.old" --new="$F.new" --log-file=stdout --report-file=report.txt
  ./inspect symfile diff --old="$F.old" --new="$F.new" --log-file=stdout
  RESULT=$(grep -c FAIL report.txt)
  REPORT=$(cat report.txt)
  [ "$RESULT" -ne 0 ] && cat report.txt && gh pr review "$GITHUB_HEAD_REF" -r -b "Proposed changes to file $F are invalid\n$REPORT"
  [ "$RESULT" -ne 0 ] && FAILED=true
done

[ $FAILED = "true" ] && exit 1
exit 0
# upload symbol info
echo Uploading symbol info
for F in $MODIFIED;
do
  FINAL_NAME=$(dirname "$F")_$(basename "$F")
  aws s3 cp "$F.new" "s3://tradingview-customers-symbolinfo/staging/$FINAL_NAME" --no-progress
  aws s3 cp "$F.new" "s3://tradingview-customers-symbolinfo/production/$FINAL_NAME" --no-progress
done

# merge PR
echo ready to merge
# gh pr merge $GITHUB_HEAD_REF --merge --delete-branch


