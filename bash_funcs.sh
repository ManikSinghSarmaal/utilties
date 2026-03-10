# USEFUL BASH FUNCTIONS TO LOAD IN YOUR BASHRC/ZSHRC 

#---------------------------------------------------------------------------------------------------------------------------
# when leaving the console clear the screen to increase privacy
#inspect pid and dump logs to a file in format YYYYMMDD_HHMMSS_<pid>.log
#---------------------------------------------------------------------------------------------------------------------------
inspect_pid () 
{ 
    local PID="$1";
    if [[ -z "$PID" || ! -d "/proc/$PID" ]]; then
        echo "Usage: inspect_pid <pid> | this dumps a log file about the process in format YYYYMMDD_HHMMSS_<pid>.log";
        return 1;
    fi;
    local TS;
    TS=$(date +"%Y%m%d_%H%M%S");
    local LOG="${TS}_${PID}.log";
    { 
        echo "==============================";
        echo " Process Inspection Snapshot";
        echo "==============================";
        echo "Timestamp : $(date)";
        echo "PID       : $PID";
        echo;
        ps -p "$PID" -o pid,ppid,user,group,%cpu,%mem,vsz,rss,etime,stat,cmd;
        echo;
        echo "===== process status (/proc/$PID/status) =====";
        cat /proc/"$PID"/status;
        echo;
        echo "===== memory maps (/proc/$PID/maps) =====";
        cat /proc/"$PID"/maps;
        echo;
        echo "===== open file descriptors (/proc/$PID/fd) =====";
        ls --color=auto -l /proc/"$PID"/fd;
        echo;
        echo "===== lsof (open files & sockets) =====";
        lsof -p "$PID" 2> /dev/null;
        echo;
        echo "===== mount points (/proc/$PID/mountinfo) =====";
        cat /proc/"$PID"/mountinfo;
        echo;
        echo "===== limits (/proc/$PID/limits) =====";
        cat /proc/"$PID"/limits;
        echo;
        echo "===== cmdline =====";
        tr '\0' ' ' < /proc/"$PID"/cmdline;
        echo;
        echo;
        echo "===== environment (names only) =====";
        tr '\0' '\n' < /proc/"$PID"/environ | cut -d= -f1;
        echo;
        echo "===== threads =====";
        ls --color=auto /proc/"$PID"/task | wc -l;
        echo;
        echo "===== end of snapshot ====="
    } > "$LOG";
    echo "Process snapshot written to: $LOG"
}


#---------------------------------------------------------------------------------------------------------------------------
#download youtube video using yt-dlp api
#---------------------------------------------------------------------------------------------------------------------------
download_video() {
    URL="$1"
    START="$2"
    END="$3"

    # If no URL was provided, show usage
    if [ -z "$URL" ]; then
        echo "Usage: download_video <url> [start_time] [end_time]"
        return 1
    fi

    # CASE 1 — Full video (only URL)
    if [ -z "$START" ]; then
        echo "Downloading full video..."
        yt-dlp -f "bestvideo+bestaudio/best" "$URL"
        return
    fi

    # CASE 2 — Start timestamp only (no end time)
    if [ -z "$END" ]; then
        echo "Downloading video from $START..."
        yt-dlp -f "bestvideo+bestaudio/best" \
               --download-sections "*$START-" \
               "$URL"
        return
    fi

    # CASE 3 — Start + End timestamps
    echo "Downloading clip from $START to $END..."
    yt-dlp -f "bestvideo+bestaudio/best" \
           --download-sections "*$START-$END" \
           "$URL"
}


#---------------------------------------------------------------------------------------------------------------------------
# custom fuzzy search implementation for bash functions
#---------------------------------------------------------------------------------------------------------------------------
ffunc() {
  local file="${1:-$HOME/.bash_functions}"
  [ -f "$file" ] || { echo "file not found: $file"; return 1; }

  # list: "LINE:NAME"
  local list
  list=$(perl -ne 'print "$.:$1\n" if /^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)\s*\{/' "$file")
  [ -z "$list" ] && { echo "no functions found in $file"; return 0; }

  # fall back to plain list if fzf missing
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not found — install it (brew install fzf) for fuzzy navigation"
    echo "$list" | column -t -s:
    return 0
  fi

  # Choose with fzf. The preview shows the file (you can tweak)
  local choice
  choice=$(printf "%s\n" "$list" | fzf --height 40% --reverse --ansi \
    --preview "nl -ba $file | sed -n '1,250p'" \
    --prompt="Select function > ")

  [ -z "$choice" ] && return 0

  local lineno name
  lineno="${choice%%:*}"
  name="${choice##*:}"

  # open editor at line
  ${EDITOR:-vim} +$lineno "$file"
}
# convenience alias, add this to .bashrc or .zshrc to load this
alias ef='ffunc'


#---------------------------------------------------------------------------------------------------------------------------
#match /var/lib/docker/id to the docker contnainer name
#---------------------------------------------------------------------------------------------------------------------------
match() {
  local needle="$1"

  docker ps -aq | while read cid; do
    if docker inspect "$cid" | grep -q "$needle"; then
      local name
      name=$(docker inspect "$cid" --format='{{.Name}}')
echo "Used by container CID=$cid [$name]"
    fi
  done
}


#---------------------------------------------------------------------------------------------------------------------------
# Rclone Helpers for google drive management
#---------------------------------------------------------------------------------------------------------------------------
# Detect --shared / -s
_drive_shared_flag() {
    for arg in "$@"; do
        if [[ "$arg" == "--shared" || "$arg" == "-s" ]]; then
            echo "--drive-shared-with-me"
            return 0
        fi
    done
    echo ""
}

# Detect --help / -h
_has_help_flag() {
    for arg in "$@"; do
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            return 0
        fi
    done
    return 1
}

# Strip flags (--shared/-s/--help/-h)
_strip_flags() {
    local cleaned=()
    for arg in "$@"; do
        [[ "$arg" == "--shared" || "$arg" == "-s" || "$arg" == "--help" || "$arg" == "-h" ]] && continue
        cleaned+=("$arg")
    done
    printf "%s\n" "${cleaned[@]}"
}

# -----------------------------
# upload_big_file
# -----------------------------
upload_big_file() {
    if _has_help_flag "$@"; then
        cat <<EOF
Usage:
  upload_big_file [-s|--shared] <local_file> <remote_path>

Description:
  Uploads a large file to Google Drive using resumable upload options.

Examples:
  upload_big_file ./big.zip DEST/PATH/
  upload_big_file -s ./big.zip SharedFolder/DEST/
EOF
        return 0
    fi


    # Clean args (remove flags)
    mapfile -t args < <(_strip_flags "$@")

    if [[ ${#args[@]} -lt 2 ]]; then
        echo "Error: Missing arguments."
        echo "Try: upload_big_file -h"
        return 1
    fi

    local file="${args[0]}"
    local remote_path="${args[1]}"


    rclone copy "$file" "manik@meta:$remote_path" \
        -P \
        --transfers 1 \
        --retries 20 \
        --low-level-retries 20 \
        --drive-chunk-size 128M \
        --multi-thread-streams 0 \
        --fast-list
}

# -----------------------------
# find_in_drive
# -----------------------------
find_in_drive() {
    if _has_help_flag "$@"; then
        cat <<EOF
Usage:
  find_in_drive [-s|--shared] <search_pattern>

Description:
  Search filenames in Google Drive using rclone ls + grep.

Examples:
  find_in_drive dataset
  find_in_drive -s dataset
EOF
        return 0
    fi

    local shared_flag
    shared_flag=$(_drive_shared_flag "$@")

    mapfile -t args < <(_strip_flags "$@")

    if [[ ${#args[@]} -lt 1 ]]; then
        echo "Error: Missing search_pattern."
        echo "Try: find_in_drive -h"
        return 1
    fi

    local pattern="${args[0]}"

    echo "Searching Google Drive for: $pattern"
    [[ -n "$shared_flag" ]] && echo "Mode: Shared-with-me enabled ✅"

    rclone ls manik@meta: $shared_flag | grep -i "$pattern"
}

# -----------------------------
# upload_file
# -----------------------------
upload_file() {
    if _has_help_flag "$@"; then
        cat <<EOF
Usage:
  upload_file [-s|--shared] <local_file_or_folder> <remote_path>

Description:
  Uploads a file/folder to Google Drive.
  If size > 500MB → automatically uses upload_big_file.

Examples:
  upload_file ./file.zip DEST/PATH/
  upload_file -s ./file.zip SharedFolder/DEST/
  upload_file ./folder DEST/PATH/
EOF
        return 0
    fi


    mapfile -t args < <(_strip_flags "$@")

    if [[ ${#args[@]} -lt 2 ]]; then
        echo "Error: Missing arguments."
        echo "Try: upload_file -h"
        return 1
    fi

    local path="${args[0]}"
    local remote_path="${args[1]}"

    if [[ ! -e "$path" ]]; then
        echo "Error: '$path' does not exist."
        return 1
    fi

    local size_mb
    size_mb=$(du -sm "$path" | awk '{print $1}')

    echo "Detected size: $size_mb MB"

    if (( size_mb > 500 )); then
        echo "'$path' is larger than 500MB. Using upload_big_file..."
        upload_big_file "$path" "$remote_path"
    else
        echo "Uploading NORMAL item: $path → manik@meta:$remote_path"
        rclone copy "$path" "manik@meta:$remote_path" -P --fast-list
    fi
}

copy_file(){
local path="$1"
local dest_dir="$2"

if [[ ! -e "$dest_dir" ]]; then
	echo "Error: destination deirectory -> '$dest_dir' not defined"
	return 1
fi
rclone copy manik@meta:"$path" "$dest_dir" -P -v

}


#---------------------------------------------------------------------------------------------------------------------------
# docker exec utility
#---------------------------------------------------------------------------------------------------------------------------

dockerexec() {
    if [ -z "$1" ]; then
        echo "Usage: dockerishaan <container_name> [command...]"
        return 1
    fi
    local container="$1"
    shift
    docker exec -it \
        -e USER=manik \
        -e HOME=/workspace \
        "$container" "${@:-bash}"
}

#---------------------------------------------------------------------------------------------------------------------------
# Git commit utility {stages changes automatically and shows status if nothing to commit}
# ---------------------------------------------------------------------------------------------------------------------------
commit() {
  if [ -z "$*" ]; then
    echo "Usage: commit \"message\""
    return 1
  fi

  git add -A

  if git diff --cached --quiet; then
    echo "Nothing to commit."
    return 0
  fi

  git commit -m "$*"
}


#---------------------------------------------------------------------------------------------------------------------------
# list commits in local mirror that differ from remote
#---------------------------------------------------------------------------------------------------------------------------
list_mirror_commits() {
  git for-each-ref --format="%(refname:short)" refs/heads |
  while read -r ref; do
    echo "Ref: $ref"

    if git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
      git log --oneline --graph --decorate origin/$ref..$ref
    else
      echo "  (no corresponding origin branch)"
      git log --oneline --graph --decorate "$ref"
    fi

    echo
  done
}
