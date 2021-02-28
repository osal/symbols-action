#!/bin/bash

git version
gh --version
aws --version
jq --version

PR_NUMBER=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
git fetch origin --depth=1 > /dev/null 2>&1

# check for deleted JSON files
DELETED=$(git diff --name-only --diff-filter=D origin/master)
if [ -n "$DELETED" ]; then
  echo "### :red_circle: Deleting JSON files is forbidden" > deleted_report
  echo "#### These files were deleted:" >> deleted_report
  echo "$DELETED" >> deleted_report
  DELETED_REPORT=$(cat deleted_report)
  gh pr review $PR_NUMBER -r -b "$DELETED_REPORT"
  exit 1
fi

# check for renamed JSON files
RENAMED=$(git diff --name-only --diff-filter=R origin/master)
if [ -n "$RENAMED" ]; then
  echo "### :red_circle: Renaming JSON files is forbidden" > renamed_report
  echo "#### These files were renamed:" >> renamed_report
  echo "$RENAMED" >> renamed_report
  RENAMED_REPORT=$(cat renamed_report)
  gh pr review $PR_NUMBER -r -b "$RENAMED_REPORT"
  exit 1
fi

# check for added JSON files
ADDED=$(git diff --name-only --diff-filter=A origin/master)
if [ -n "$ADDED" ]; then
  echo "### :red_circle: Adding JSON files is forbidden" > added_report
  echo "#### These files were added:" >> added_report
  echo "$ADDED" >> added_report
  ADDED_REPORT=$(cat added_report)
  gh pr review $PR_NUMBER -r -b "$ADDED_REPORT"
  exit 1
fi

# validate modified files
MODIFIED=$(git diff --name-only origin/master | grep ".json$")
if [ -z "$MODIFIED" ]; then
  echo No symbol info files were modified
  gh pr review $PR_NUMBER -r -b "No symbol info files (JSON) were modified"
  exit 1
fi

# save new versions
for F in $MODIFIED; do cp "$F" "$F.new"; done

# save old versions
git checkout -b old origin/master
for F in $MODIFIED; do cp "$F" "$F.old"; done

# download inspect tool
aws s3 cp "$S3_BUCKET_INSPECT/inspect_md" ./inspect --no-progress && chmod +x ./inspect
echo inpsect info: $(./inspect version)

# check files
FAILED=false

for F in $MODIFIED; do
  echo Checking "$F"
  ./inspect symfile --old="$F.old" --new="$F.new" --log-file=stdout --report-file=report.txt --report-format=github
  ./inspect symfile diff --old="$F.old" --new="$F.new" --log-file=stdout
  RESULT=$(grep -c FAIL report.txt)
  echo "#### $F" >> full_report.txt
  cat report.txt >> full_report.txt
  [ "$RESULT" -ne 0 ] && FAILED=true
done

FULL_REPORT=$(cat full_report.txt)

[ $FAILED = "true" ] && gh pr review $PR_NUMBER -r -b "$FULL_REPORT"
[ $FAILED = "false" ] && gh pr review $PR_NUMBER -a -b "$FULL_REPORT"
[ $FAILED = "true" ] && echo some tests have failed && exit 1

# upload symbol info
echo uploading symbol info
INTEGRATION_NAME=${GITHUB_REPOSITORY##*/}
for F in $MODIFIED;
do
  FINAL_NAME=${INTEGRATION_NAME}_$(basename "$F")
  echo uploading $F.new to $S3_BUCKET_SYMBOLS/$SYMBOLS_PREFIX/$FINAL_NAME
  # aws s3 cp "$F.new" "$S3_BUCKET_SYMBOLS/$SYMBOLS_PREFIX/$FINAL_NAME" --no-progress
done

# merge PR
echo ready to merge
# gh pr merge $PR_NUMBER --merge --delete-branch
