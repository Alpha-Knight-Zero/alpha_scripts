#!/bin/bash

###############################################################################
# diffsFromCommitByAuthor.sh — View Git Diffs or Final Files by Author in VS Code
#
# 📌 Description:
#    This script shows either:
#      1. Per-commit file diffs made by a specific author after a given Git commit.
#      2. OR opens the latest version of all files changed by that author in that range.
#      NOTE : It excludes the commits attributed to more than 1 person, like commits from merging chnages done by others.
#
# ✅ Prerequisites:
#    - Git, VS Code CLI (`code`), and Bash shell
#
# 🔧 Installation:
#    chmod +x diffsFromCommitByAuthor.sh
#
# 🚀 Usage:
#    ./diffsFromCommitByAuthor.sh <commit-sha> "<author-name-or-email>"
#
# Developer name: Pushkal Pandey (pushkaldkpandey333@gmail.com)
###############################################################################

export GIT_PAGER=cat 

# --- Input Validation and Setup ---
START_COMMIT=$1
AUTHOR=$2

if [[ -z "$START_COMMIT" || -z "$AUTHOR" ]]; then
  echo "Usage: $0 <commit-sha> \"<author-name-or-email>\""
  exit 1
fi

TMP_DIR=$(mktemp -d)

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- User Mode Selection ---
echo -e "${CYAN}Choose an option:${NC}"
echo "1) View file diffs in VS Code (default)"
echo "2) Open modified files (latest version only)"
read -p "Enter 1 or 2: " MODE
MODE=${MODE:-1} # Default to option 1

# --- Get Commits by Author ---
commits=$(git log "${START_COMMIT}..HEAD" --no-merges --author="$AUTHOR" --reverse --pretty=format:"%H")

if [[ -z "$commits" ]]; then
  echo -e "${YELLOW}No commits found by '$AUTHOR' after $START_COMMIT${NC}"
  exit 0
fi

# --- Mode 2: Open Latest Version of Modified Files ---
if [ "$MODE" = "2" ]; then
  echo -e "${CYAN}Collecting final versions of files changed by '$AUTHOR' after $START_COMMIT...${NC}"
  
  # Collect all changed files across all commits
  files=()
  for commit in $commits; do
    changed=$(git show --pretty="" --name-only "$commit")
    files+=($changed)
  done

  # Get unique files to avoid opening duplicates
  unique_files=($(printf "%s\n" "${files[@]}" | sort -u))

  echo -e "${CYAN}Found ${#unique_files[@]} unique files.${NC}"

  file_count=0
  total_files=${#unique_files[@]}

  for file in "${unique_files[@]}"; do
    file_count=$((file_count + 1))
    
    # Skip if the file was deleted (not present in HEAD)
    if ! git ls-tree -r HEAD --name-only | grep -Fxq "$file"; then
      echo -e "❌ Skipping deleted file: ${RED}${file_count}/${total_files} - $file${NC}"
      continue
    fi

    # Create a safe temporary file path
    safe_file="${TMP_DIR}/$(echo "$file" | tr '/' '_' | tr ' ' '_')"
    git show "HEAD:$file" > "$safe_file" 2>/dev/null || continue

    if file "$safe_file" | grep -q "binary"; then
      echo -e "⚠️  Skipping binary file: ${YELLOW}${file_count}/${total_files} - $file${NC}"
      continue
    fi

    echo -e "📂 Opening: ${BLUE}${file_count}/${total_files} - $file${NC}"
    code "$safe_file" --new-window --wait
  done

  rm -rf "$TMP_DIR"
  exit 0
fi

# --- Mode 1: Diff View Commit by Commit ---
echo -e "${CYAN}Processing diffs by '$AUTHOR' after $START_COMMIT...${NC}"

for commit in $commits; do
  parent=$(git rev-parse "${commit}^")

  echo ""
  echo -e "${BOLD}===================="
  echo -e "📝 Commit: ${CYAN}$commit${NC}"
  echo -e "====================${NC}"

  message=$(git log -1 --pretty=format:"%s" "$commit")
  echo -e "${BOLD}Message:${NC} $message"

  # Display commit statistics with colored insertions/deletions
  git show --stat --oneline --no-color "$commit" | tail -n +2 | while IFS= read -r line; do
    if [[ "$line" =~ ([0-9]+)\ insertions* ]]; then
      line=${line//"${BASH_REMATCH[0]}"/"${GREEN}${BASH_REMATCH[0]}${NC}"}
    fi
    if [[ "$line" =~ ([0-9]+)\ deletions* ]]; then
      line=${line//"${BASH_REMATCH[0]}"/"${RED}${BASH_REMATCH[0]}${NC}"}
    fi
    if [[ "$line" =~ \| ]]; then
      file_name=$(echo "$line" | cut -d'|' -f1 | xargs)
      rest=$(echo "$line" | cut -d'|' -f2-)
      echo -e "📄 ${BLUE}${file_name}${NC} | $rest"
    else
      echo -e "$line"
    fi
  done

  echo ""

  files=$(git show --pretty="" --name-only "$commit")
  
  # Calculate total files for the current commit to display x/y format
  commit_total_files=$(echo "$files" | wc -l | xargs)
  commit_file_count=0

  for file in $files; do
    commit_file_count=$((commit_file_count + 1))
    safe_filename=$(echo "$file" | tr '/' '_' | tr ' ' '_')
    tmp_parent="${TMP_DIR}/${safe_filename}_parent"
    tmp_commit="${TMP_DIR}/${safe_filename}_commit"
    file_deleted_in_commit=false

    # Check if the file was deleted in this commit
    if ! git ls-tree "$commit" -- "$file" >/dev/null; then
      file_deleted_in_commit=true
    fi

    if [ "$file_deleted_in_commit" = true ]; then
      git show "${parent}:${file}" > "$tmp_parent" 2>/dev/null || echo "" > "$tmp_parent"
      echo "" > "$tmp_commit" # Represents the deleted state
      echo -e "❌ File deleted: ${RED}$file${NC} — showing removal diff (${commit_file_count}/${commit_total_files})"
    else
      git show "${parent}:${file}" > "$tmp_parent" 2>/dev/null || echo "" > "$tmp_parent"
      git show "${commit}:${file}" > "$tmp_commit" 2>/dev/null || echo "" > "$tmp_commit"
    fi

    # Check for binary files
    if file "$tmp_parent" "$tmp_commit" | grep -q "binary"; then
      echo -e "⚠️  Skipping binary file: ${YELLOW}$file${NC} (${commit_file_count}/${commit_total_files})"
      continue
    fi

    echo -e "🔍 Opening diff for ${BLUE}$file${NC}... (${commit_file_count}/${commit_total_files})"
    code --diff "$tmp_parent" "$tmp_commit" --new-window --wait
  done
done

rm -rf "$TMP_DIR"