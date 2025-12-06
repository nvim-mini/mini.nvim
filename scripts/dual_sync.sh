# Perform local sync of standalone repositories, but only if on `main` branch
branch="$( git symbolic-ref --short HEAD )"
if [[ $branch != "main" ]]
then
  printf "\nDo sync only for 'main' branch, not '$branch'\n\n"
  exit 2
fi

repos_dir=dual/repos
patches_dir=dual/patches

mkdir -p $repos_dir
mkdir -p $patches_dir

sync_module () {
  # First argument is a string with module name. Others - extra paths to track
  # for module.
  module=$1
  shift

  repo="$( realpath $repos_dir/mini.$module )"
  patch="$( realpath $patches_dir/mini.$module.patch )"

  # Make patch with commits from 'sync' branch to current HEAD which affect
  # files related to the module
  git format-patch sync..HEAD --output $patch -- \
    lua/mini/$module.lua \
    doc/mini-$module.txt \
    readmes/mini-$module.md \
    LICENSE \
    $@

  # Do nothing if patch is empty
  if [[ ! -s $patch ]]
  then
    rm $patch
    # Return early to skip unnecessary repo pull (saves time)
    return
  fi

  printf "\n\033[1mmini.$module\033[0m\n"

  # Tweak patch:
  # - Move 'readmes/mini-xxx.md' to 'README.md'. This should modify only patch
  #   metadata, and not text (assuming it uses 'readmes/mini-xxx.md' on
  #   purpose; as in "use [this link](https://.../readmes/mini-xxx.md)").
  sed -i "s/readmes\/mini-$module\.md\([^)]\)/README.md\\1/" $patch
  sed -i "s/readmes\/mini-$module\.md$/README.md/" $patch
  # - Move all known relative links one step higher (and hope that it doesn't
  #   occur anywhere else in patch). NOTE: There can be other relative links
  #   which should be corrected manually
  sed -i "s/\[Documentation\](\.\.\/doc/[Documentation](doc/" $patch

  # Possibly pull repository
  if [[ ! -d $repo ]]
  then
    printf "Pulling\n"
    # Handle 'mini.git' differently because GitHub repo is named 'mini-git'
    # (".git" suffix is not allowed as repo name on GitHub)
    if [ $module = "git" ]; then github_repo="mini-git"; else github_repo="mini.$module"; fi
    git clone --filter=blob:none https://github.com/nvim-mini/$github_repo.git $repo >/dev/null 2>&1
  fi

  # Apply patch
  printf "Applying patch\n"
  cd $repo > /dev/null
  git am $patch
  cd - > /dev/null
}

sync_module "ai"
sync_module "align"
sync_module "animate"
sync_module "base16" colors/minischeme.lua colors/minicyan.lua
sync_module "basics"
sync_module "bracketed"
sync_module "bufremove"
sync_module "clue"
sync_module "cmdline"
sync_module "colors"
sync_module "comment"
sync_module "completion"
sync_module "cursorword"
sync_module "deps" scripts/init-deps-example.lua
sync_module "diff"
sync_module "doc"
sync_module "extra"
sync_module "files"
sync_module "fuzzy"
sync_module "git"
sync_module "hipatterns"
sync_module "hues" colors/miniwinter.lua colors/minispring.lua colors/minisummer.lua colors/miniautumn.lua colors/randomhue.lua
sync_module "icons"
sync_module "indentscope"
sync_module "jump"
sync_module "jump2d"
sync_module "keymap"
sync_module "map"
sync_module "misc"
sync_module "move"
sync_module "notify"
sync_module "operators"
sync_module "pairs"
sync_module "pick"
sync_module "sessions"
sync_module "snippets"
sync_module "splitjoin"
sync_module "starter"
sync_module "statusline"
sync_module "surround"
sync_module "tabline"
sync_module "test"
sync_module "trailspace"
sync_module "visits"
