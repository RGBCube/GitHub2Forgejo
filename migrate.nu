#!/usr/bin/env nu

def str-or [default: closure] {
  if $in == null or $in == "<NONE>" {
    do $default
  } else {
    $in
  }
}

# Migrates a GitHub users repositories to a Gitea or Forgejo instance.
def main [
  --github-user: string = "<NONE>"  # The user to migrate from.
  --github-token: string = "<NONE>" # An access token for fetching private repositories. Optional.
  --gitea-url: string = "<NONE>"    # The URL to the Gitea or Forgejo instance
  --gitea-user: string = "<NONE>"   # The user to migrate the repositories to.
  --gitea-token: string = "<NONE>"  # An access token for the user to actually insert repositories to.
  --strategy: string = "<NONE>"     # The strategy. Valid options are "Mirrored" or "Cloned" (case sensitive).
  ...repo_urls: string              # The GitHub repo URLs to migrate to Gitea or Forgejo. If not given, all will be fetched.
] {
  let github_user = $github_user | str-or { input $"(ansi red)GitHub username: (ansi reset)" }
  let github_token = $github_token | str-or { input $"(ansi red)GitHub access token (ansi yellow)\((ansi blue)optional, only used for private repositories(ansi yellow))(ansi red): (ansi reset)" }

  let gitea_url = $gitea_url | str-or { input $"(ansi green)Gitea instance URL: (ansi reset)" } | str trim --right --char "/"

  let gitea_user = $gitea_user | str-or { input $"(ansi green)Gitea username or organization to migrate to: (ansi reset)" }
  let gitea_token = $gitea_token | str-or { input $"(ansi green)Gitea access token: (ansi reset)" }

  let gitea_uid = (
    http get $"($gitea_url)/api/v1/users/($gitea_user)"
    -H [ Authorization $"token ($gitea_token)" ]
  ) | get --ignore-errors id

  if $gitea_uid == null {
    echo "Invalid Gitea username or password"
    exit 1
  }

  let strategy = $strategy | str-or { [ Mirrored Cloned ] | input list $"(ansi cyan)Should the repos be mirrored, or just cloned once? (ansi reset)" }

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

    let repo_is_private = if $github_token == "" {
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
        mirror: ($strategy == "Mirrored")
        private: $repo_is_private
        uid: $gitea_uid

        repo_owner: $gitea_user
        repo_name: $repo_name
      }
    )

    echo $" (ansi green)Success!"

    echo ($response | to json)

    # TODO: Handle ratelimits, 409's and access failures. Also print a
    # nice message and options on what to do next on error.
  }
}
