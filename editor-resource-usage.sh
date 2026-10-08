#!/usr/bin/env bash
# macOS/Linux, Bash 3.2+. Requires only ps, awk, date, sleep and mktemp.
# Read-only sampling of current-user editor processes and their descendants.
set -eu
export LC_ALL=C
interval=2
samples=5
vs_pids=''
nv_pids=''
usage() {
  cat <<'EOF'
Usage: bash editor-resource-usage.sh [options]
  --interval SECONDS   Seconds between samples (positive integer; default 2)
  --samples COUNT      Number of samples (positive integer; default 5)
  --vscode-pid PID     Use this VS Code root instead of automatic discovery
  --nvim-pid PID       Use this Neovim root instead of automatic discovery
                       PID options can be repeated to select several instances.
  -h, --help

Includes descendant language servers, helpers and integrated terminals.
RAM = summed resident memory (RSS); shared pages may be counted more than once.
CPU = CPU time gained / elapsed wall time; 100% means one full logical core.
Only processes belonging to your user are measured. Does not launch editors.
EOF
}
positive() { case "$1" in ''|*[!0-9]*|0*) return 1 ;; *) return 0 ;; esac; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --interval|--samples|--vscode-pid|--nvim-pid)
      [ "$#" -ge 2 ] && positive "$2" || { usage >&2; exit 2; }
      case "$1" in
        --interval) interval=$2 ;; --samples) samples=$2 ;;
        --vscode-pid) vs_pids="$vs_pids $2" ;; --nvim-pid) nv_pids="$nv_pids $2" ;;
      esac
      shift 2 ;;
    *) usage >&2; exit 2 ;;
  esac
done
os=$(uname -s)
case "$os" in Linux|Darwin) ;; *) echo 'Requires macOS or Linux.' >&2; exit 1 ;; esac
hz=100
if [ "$os" = Linux ]; then hz=$(getconf CLK_TCK); fi
user_id=$(id -u)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/editor-resources.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot() {
  # Explicit fields and wide output work with both GNU and BSD ps.
  ps -axww -o pid= -o ppid= -o uid= -o rss= -o time= -o comm= > "$tmp/ps"
  awk -v uid="$user_id" -v os="$os" -v hz="$hz" '
    function seconds(t, a,n,d) {
      d=0; if(index(t,"-")) {split(t,a,"-"); d=a[1]*86400; t=a[2]}
      n=split(t,a,":")
      if(n==3) return d+a[1]*3600+a[2]*60+a[3]
      if(n==2) return d+a[1]*60+a[2]
      return d+t
    }
    $3==uid {
      pid=$1; parent=$2; rss=$4; cpu=seconds($5); birth="unknown"
      command=$0; sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/,"",command)
      if(os=="Linux") {
        file="/proc/" pid "/stat"
        if((getline stat < file)<=0) {close(file); next}
        close(file); sub(/^.*\) /,"",stat); split(stat,a," ")
        cpu=(a[12]+a[13])/hz; birth=a[20]
      }
      # Tabs delimit records; commands can contain spaces.
      gsub(/\t/," ",command)
      printf "%d\t%d\t%d\t%.6f\t%s\t%s\n",pid,parent,rss,cpu,birth,command
    }' "$tmp/ps" > "$1"
}
clock() {
  if [ "$os" = Linux ]; then awk '{print $1}' /proc/uptime
  else date +%s; fi
}

printf 'Sampling every %ss for %s samples. Use both editors on the same project/workload.\n' "$interval" "$samples"
printf '%-8s %-12s %7s %12s %10s\n' SAMPLE EDITOR PROCS RAM_MiB CPU_pct
snapshot "$tmp/before"
before_time=$(clock)
: > "$tmp/totals"
step=1
while [ "$step" -le "$samples" ]; do
  sleep "$interval"
  snapshot "$tmp/after"
  after_time=$(clock)
  awk -F '\t' -v previous="$tmp/before" -v vs="$vs_pids" -v nv="$nv_pids" \
    -v self="$$" -v t0="$before_time" -v t1="$after_time" -v step="$step" \
    -v totals="$tmp/totals" -v details="$tmp/details" '
    FILENAME==previous {oldcpu[$1]=$4; oldbirth[$1]=$5; next}
    {
      pid=$1; p[pid]=$2; ram[pid]=$3; cpu[pid]=$4; birth[pid]=$5; cmd[pid]=$6
      name=cmd[pid]; sub(/^.*\//,"",name)
      if(vs=="" && (name=="code" || name=="code-insiders" || cmd[pid] ~ /\/Visual Studio Code( - Insiders)?\.app\//)) group[pid]=1
      if(nv=="" && name=="nvim") group[pid]=2
    }
    END {
      n=split(vs,a," "); for(i=1;i<=n;i++) if(a[i] in p) group[a[i]]=1
      n=split(nv,a," "); for(i=1;i<=n;i++) if(a[i] in p) group[a[i]]=2
      ignored[self]=1
      # Repeated passes handle arbitrary ps ordering and deep process trees.
      do {
        changed=0
        for(pid in p) {
          if(!ignored[pid] && ignored[p[pid]]) {ignored[pid]=1; changed=1}
          if(!group[pid] && group[p[pid]]) {group[pid]=group[p[pid]]; changed=1}
        }
      } while(changed)
      dt=t1-t0; if(dt<=0) dt=1
      printf "" > details
      for(pid in p) if(group[pid] && !ignored[pid]) {
        g=group[pid]; count[g]++; memory[g]+=ram[pid]; percent=0
        # New processes lack a baseline; exited processes cannot be sampled.
        if(pid in oldcpu && birth[pid]==oldbirth[pid] && cpu[pid]>=oldcpu[pid]) percent=100*(cpu[pid]-oldcpu[pid])/dt
        else unmeasured[g]++
        load[g]+=percent
        printf "%-8s %7d %10.1f %9.1f  %s\n",g==1?"VS Code":"Neovim",pid,ram[pid]/1024,percent,cmd[pid] >> details
      }
      for(g=1;g<=2;g++) {
        label=g==1?"VS Code":"Neovim"
        printf "%-8d %-12s %7d %12.1f %10.1f\n",step,label,count[g],memory[g]/1024,load[g]
        printf "%d %.6f %.6f %.6f %d %d\n",g,memory[g]/1024,load[g],dt,count[g],unmeasured[g] >> totals
      }
    }' "$tmp/before" "$tmp/after"
  mv "$tmp/after" "$tmp/before"
  before_time=$after_time
  step=$((step + 1))
done
awk '
  {g=$1; n[g]++; mem[g]+=$2; if($2>peak[g]) peak[g]=$2; work[g]+=$3*$4; duration[g]+=$4; seen[g]+=$5; fresh[g]+=$6}
  END {
    printf "\n%-12s %14s %14s %14s\n","SUMMARY","Avg RAM MiB","Peak RAM MiB","Avg CPU %"
    for(g=1;g<=2;g++) {
      printf "%-12s %14.1f %14.1f %14.1f\n",g==1?"VS Code":"Neovim",mem[g]/n[g],peak[g],work[g]/duration[g]
      if(!seen[g]) printf "  No %s processes found.\n",g==1?"VS Code":"Neovim"
      if(fresh[g]) printf "  %d process observations lacked a CPU baseline.\n",fresh[g]
    }
  }' "$tmp/totals"
printf '\nFinal sample: editor, PID, RSS MiB, interval CPU %% and executable\n'
sort "$tmp/details"
printf '\nRSS can double-count shared memory; peak is the highest sampled total.\n'
printf 'Descendants include terminals/jobs. Remote or detached servers are excluded.\n'
printf 'Short-lived/exited processes may be missed. macOS CPU timing has coarser resolution.\n'

