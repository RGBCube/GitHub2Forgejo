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
def main [
  ...repo_urls: string # The GitHub repo URLs to migrate to Gitea or Forgejo. If not given, all will be fetched.
] {
  let github_user = $env | get -i GITHUB_USER | or-default { input $"(ansi red)GitHub username: (ansi reset)" }
  let github_token = $env | get -i GITHUB_TOKEN | or-default { input $"(ansi red)GitHub access token (ansi yellow)\((ansi blue)optional, only used for private repositories(ansi yellow))(ansi red): (ansi reset)" }

  let gitea_url = $env | get -i GITEA_URL | or-default { input $"(ansi green)Gitea instance URL \(with https://): (ansi reset)" } | str trim --right --char "/"

  let gitea_user = $env | get -i GITEA_USER | or-default { input $"(ansi green)Gitea username or organization to migrate to: (ansi reset)" }
  let gitea_token = $env | get -i GITEA_TOKEN | or-default { input $"(ansi green)Gitea access token: (ansi reset)" }

  let gitea_uid = (
    http get $"($gitea_url)/api/v1/users/($gitea_user)"
    -H [ Authorization $"token ($gitea_token)" ]
  ) | get --ignore-errors id

  if $gitea_uid == null {
    echo "Invalid Gitea username or password"
    exit 1
  }

  let strategy = $env | get -i STRATEGY | or-default { [ Mirrored Cloned ] | input list $"(ansi cyan)Should the repos be mirrored, or just cloned once? (ansi reset)" } | str downcase

  let repo_urls = if ($repo_urls | length) != 0 {
    $repo_urls
  } else {
    if $github_token != "" {
      (
        http get $"https://api.github.com/users/($github_user)/repos?per_page=100"
        -H [ Authorization $"token ($github_token)" ]
      )
      | get html_url
    } else {
      http get $"https://api.github.com/users/($github_user)/repos?per_page=100"
      | get html_url
    }
  }

  $repo_urls | each {|url|
    let repo_name = $url | split row "/" | last

    let repo_is_private = if ($github_token | is-empty) {
      false
    } else {
      (
        http get ("https://api.github.com/repos/" + $github_user + "/" + $repo_name)
        -H [ Authorization $"token ($github_token)" ]
      ).private
    }

    let url = if not $repo_is_private {
      $url
    } else {
      $"https://($github_token)@github.com/($github_user)/($repo_name)"
    }

    print --no-newline $"(ansi blue)($strategy | str replace "ed" "ing") ([public private] | get ($repo_is_private | into int)) repository ($url) to ($gitea_url)/($gitea_user)/($repo_name)..."

    let response = (
      http post $"($gitea_url)/api/v1/repos/migrate"
      --allow-errors
      -t application/json
      -H [
        Authorization $"token ($gitea_token)"
      ]
      {
        clone_addr: $url
        mirror: ($strategy != "cloned")
        private: $repo_is_private
        uid: $gitea_uid

        repo_owner: $gitea_user
        repo_name: $repo_name
      }
    )

    let error_message = ($response | get -i message)
    if ($error_message != null and $error_message =~ "already exists") {
      print $" (ansi yellow)Already mirrored!"
    } else if ($error_message != null) {
      print $" (ansi red)Unknown error: ($error_message)"
    } else {
      print $" (ansi green)Success!"
    }
  }
}
