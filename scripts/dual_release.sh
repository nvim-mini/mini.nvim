# Make release from current commits
# **IMPORTANT**: sync repos (`make dual_sync` and `make dual_push`) before this

# Register tag name and message as script arguments
if [ -z "$1" ] || [ -z "$2" ]
then
  printf "Supply tag name and message as script arguments\n"
  exit 2
fi
tag_name=$1
tag_message=$2

repos_dir=dual/repos
mkdir -p $repos_dir

release_module () {
  # First argument is a string with module name
  module=$1
  shift

  repo="$( realpath $repos_dir/mini.$module )"
  printf "\n\033[1mReleasing $( basename $repo )\033[0m\n"

  # Possibly pull whole repository
  if [[ ! -d $repo ]]
  then
    printf "\033[4mPulling missing repository\033[0m\n"
    # Handle 'mini.git' differently because GitHub repo is named 'mini-git'
    # (".git" suffix is not allowed as repo name on GitHub)
    if [ $module = "git" ]; then github_repo="mini-git"; else github_repo="mini.$module"; fi
    git clone --filter=blob:none https://github.com/nvim-mini/$github_repo.git $repo
  fi

  cd $repo > /dev/null

  # Ensure `stable` branch points to latest `main`
  printf "\033[4mMaking \`stable\` point to latest \`main\`\033[0m\n"
  git checkout main
  git pull --unshallow
  git checkout -B stable
  git checkout main
  echo ''

  # Create tag
  printf "\033[4mCreating tag\033[0m\n"
  git tag -a "$tag_name" -m "$tag_message"
  echo ''

  # Push
  printf "\033[4mPushing\033[0m\n"
  git push origin $tag_name
  git push origin stable
  echo ''

  cd - > /dev/null
}

release_module "ai"
release_module "align"
release_module "animate"
release_module "base16"
release_module "basics"
release_module "bracketed"
release_module "bufremove"
release_module "clue"
release_module "cmdline"
release_module "colors"
release_module "comment"
release_module "completion"
release_module "cursorword"
release_module "deps"
release_module "diff"
release_module "doc"
release_module "extra"
release_module "files"
release_module "fuzzy"
release_module "git"
release_module "hipatterns"
release_module "hues"
release_module "icons"
release_module "indentscope"
release_module "jump"
release_module "jump2d"
release_module "keymap"
release_module "map"
release_module "misc"
release_module "move"
release_module "notify"
release_module "operators"
release_module "pairs"
release_module "pick"
release_module "sessions"
release_module "snippets"
release_module "splitjoin"
release_module "starter"
release_module "statusline"
release_module "surround"
release_module "tabline"
release_module "test"
release_module "trailspace"
release_module "visits"
