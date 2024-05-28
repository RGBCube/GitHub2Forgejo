#!/usr/bin/env nu

def or-default [default: closure] {
  if ($in | is-empty) {
    do $default
  } else {
    $in
  }
}

# Migrates a GitHub users repositories to a Gitea or Forgejo instance.
#
# Here is the accepted environment variables, if one isn't set, it will
# be prompted for:
#
# GITHUB_USER: The user to migrate from.
# GITHUB_TOKEN: An access token for fetching private repositories. Optional.
# GITEA_URL: The URL to the Gitea or Forgejo instance
# GITEA_USER: The user to migrate the repositories to.
# GITEA_TOKEN: An access token for the user to actually insert repositories to.
# STRATEGY: The strategy. Valid options are "mirrored" or "cloned" (case insensitive).
# FORCE_SYNC: Whether to delete a mirrored repo from Gitea or Forgejo if the source on GitHub doesn't exist anymore. Must be either "true" or "false".
def main [] {
  let github_user  = $env | get -i GITHUB_USER  | or-default { input $"(ansi red)GitHub username: (ansi reset)" }
  let github_token = $env | get -i GITHUB_TOKEN | or-default { input $"(ansi red)GitHub access token (ansi yellow)\((ansi blue)optional, only used for private repositories(ansi yellow))(ansi red): (ansi reset)" }
  let gitea_url    = $env | get -i GITEA_URL    | or-default { input $"(ansi green)Gitea instance URL \(with https://): (ansi reset)" } | str trim --right --char "/"
  let gitea_user   = $env | get -i GITEA_USER   | or-default { input $"(ansi green)Gitea username or organization to migrate to: (ansi reset)" }
  let gitea_token  = $env | get -i GITEA_TOKEN  | or-default { input $"(ansi green)Gitea access token: (ansi reset)" }
  let strategy     = $env | get -i STRATEGY     | or-default { [ Mirrored Cloned ] | input list $"(ansi cyan)Should the repos be mirrored, or just cloned once?(ansi reset)" } | str downcase
  let force_sync   = $env | get -i FORCE_SYNC   | or-default { [ "Yup, delete them" Nope ] | input list $"(ansi yellow)Should mirrored repos that don't have a GitHub source anymore be deleted?(ansi reset)" } | $in != "Nope"

  def get-repos [page_nr: number] {
    if $github_token != "" {
      (http get $"https://api.github.com/user/repos?per_page=100&page=($page_nr)"
      -H [ Authorization $"token ($github_token)" ])
    } else {
      http get $"https://api.github.com/users/($github_user)/repos?per_page=100?page=($page_nr)"
      exit
    }
  }

  mut github_repos = []
  mut github_repo_page_nr = 1

  loop {
    let next_repos = get-repos $github_repo_page_nr
    $github_repos = ($github_repos | append $next_repos)

    if ($next_repos | length) >= 100 {
      $github_repo_page_nr += 1
    } else {
      break
    }
  }

  $github_repos = ($github_repos | filter { get owner.login | $in == $github_user })

  # Delete mirrored repos that do not exist on GitHub.
  if $force_sync {
    let github_repo_names = ($github_repos | get name)

    let gitea_mirrored_repos = (
      http get $"($gitea_url)/api/v1/user/repos"
        -H [ Authorization $"token ($gitea_token)" ]
      | filter { get mirror }
    )

    let gitea_not_on_github = ($gitea_mirrored_repos | filter { not ($in.name in $github_repo_names) })

    $gitea_not_on_github | each {|repo|
      print --no-newline $"(ansi red)Deleting ($gitea_url)/($repo.full_name) because the mirror source doesn't exist on GitHub anymore...(ansi reset)"

      (http delete $"($gitea_url)/api/v1/repos/($repo.full_name)"
        -H [ Authorization $"token ($gitea_token)" ])

      print $" (ansi green)Success!(ansi reset)"
    }
  }

  # Mirror repos that do exist on GitHub to Gitea.
  $github_repos | each {|repo|
    let url = if not $repo.private {
      $repo.html_url
    } else {
      $"https://($github_token)@github.com/($github_user)/($repo.name)"
    }

    print --no-newline $"(ansi blue)($strategy | str capitalize | str replace "ed" "ing") ([ public private ] | get ($repo.private | into int)) repository ($url) to ($gitea_url)/($gitea_user)/($repo.name)...(ansi reset)"

    let response = (
      http post $"($gitea_url)/api/v1/repos/migrate"
      --allow-errors
      -t application/json
      -H [ Authorization $"token ($gitea_token)" ]
      {
        clone_addr: $url
        mirror: ($strategy != "cloned")
        private: $repo.private

        repo_owner: $gitea_user
        repo_name: $repo.name
      }
    )

    let error_message = ($response | get -i message)
    if ($error_message != null and $error_message =~ "already exists") {
      print $" (ansi yellow)Already mirrored!(ansi reset)"
    } else if ($error_message != null) {
      print $" (ansi red)Unknown error: ($error_message)(ansi reset)"
    } else {
      print $" (ansi green)Success!(ansi reset)"
    }
  }

  null
}
