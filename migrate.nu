#!/usr/bin/env nu

def or-default [default: closure] {
  if ($in == null) {
    do $default
  } else {
    $in
  }
}

# Migrates a GitHub users repositories to a Forgejo instance.
#
# Accepted environment variables:
#
#   GITHUB_USER: The user to fetch the repositories from.
#   GITHUB_TOKEN: An access token for fetching private repositories. Optional.
#
#   FORGEJO_URL: The URL to the Forgejo instance. Must include the protocol (https://).
#   FORGEJO_USER: The user to migrate the repositories to.
#   FORGEJO_TOKEN: An access token for the specified user.
#
#   STRATEGY:
#     The strategy. Valid options are "mirrored" or "cloned" (case insensitive).
#     "mirrored" will mirror the repository and tell the Forgejo instance to
#     periodically update it, "cloned" will only clone once. "cloned" is
#     useful if you are never going to use GitHub again.
#
#   FORCE_SYNC:
#     Whether to delete a mirrored repo from the Forgejo instance if the
#     source on GitHub doesn't exist anymore. Must be either "true" or "false".
#
# To leave an environment variable unspecified, set it to an empty string.
def main [] {
  let github_user    = $env | get -i GITHUB_USER   | or-default { input $"(ansi red)GitHub username: (ansi reset)" }
  let github_token   = $env | get -i GITHUB_TOKEN  | or-default { input $"(ansi red)GitHub access token (ansi yellow)\((ansi blue)optional, only used for private repositories(ansi yellow))(ansi red): (ansi reset)" }
  let forgejo_url    = $env | get -i FORGEJO_URL   | or-default { input $"(ansi green)Forgejo instance URL \(with https://): (ansi reset)" } | str trim --right --char "/"
  let forgejo_user   = $env | get -i FORGEJO_USER  | or-default { input $"(ansi green)Forgejo username or organization to migrate to: (ansi reset)" }
  let forgejo_token  = $env | get -i FORGEJO_TOKEN | or-default { input $"(ansi green)Forgejo access token: (ansi reset)" }
  let strategy       = $env | get -i STRATEGY      | or-default { [ Mirrored Cloned ] | input list $"(ansi cyan)Should the repos be mirrored, or just cloned once?(ansi reset)" } | str downcase
  let force_sync     = $env | get -i FORCE_SYNC    | or-default { [ "Yup, delete them" Nope ] | input list $"(ansi yellow)Should mirrored repos that don't have a GitHub source anymore be deleted?(ansi reset)" } | $in != "Nope"

  let github_repos = do {
    def get-repos-at [page_nr: number] {
      if $github_token != "" {
        (http get $"https://api.github.com/user/repos?per_page=100&page=($page_nr)"
        -H [ Authorization $"token ($github_token)" ])
      } else {
        http get $"https://api.github.com/users/($github_user)/repos?per_page=100?page=($page_nr)"
      }
    }

    mut repos = []
    mut page_nr = 1

    loop {
      let next = get-repos-at $page_nr
      $repos = ($repos | append $next)

      if ($next | length) >= 100 {
        $page_nr += 1
      } else {
        break
      }
    }

    $repos | filter { get owner.login | $in == $github_user }
  }

  # Delete mirrored repos that do not exist on GitHub.
  if $force_sync {
    let github_repo_names = ($github_repos | get name)

    let forgejo_mirrored_repos = (
      http get $"($forgejo_url)/api/v1/user/repos"
        -H [ Authorization $"token ($forgejo_token)" ]
      | filter { get mirror }
      | filter { ($github_token != "") and not $in.private }
    )

    let forgejo_not_on_github = ($forgejo_mirrored_repos | filter { not ($in.name in $github_repo_names) })

    $forgejo_not_on_github | each {|forgejo_repo|
      print --no-newline $"(ansi red)Deleting ($forgejo_url)/($forgejo_repo.full_name) because the mirror source doesn't exist on GitHub anymore...(ansi reset)"

      (http delete $"($forgejo_url)/api/v1/repos/($forgejo_repo.full_name)"
        -H [ Authorization $"token ($forgejo_token)" ])

      print $" (ansi green_bold)Success!(ansi reset)"
    }
  }

  # Mirror repos that do exist on GitHub to Forgejo.
  $github_repos | each {|github_repo|
    print --no-newline $"(ansi blue)(
      $strategy | str capitalize | str replace "ed" "ing"
    ) (
      [ $"(ansi green)public(ansi blue)(char space)" $"(ansi red)private(ansi blue)" ] | get ($github_repo.private | into int)
    ) repository (ansi purple)($github_repo.html_url)(ansi blue) to (ansi white_bold)($forgejo_url)/($forgejo_user)/($github_repo.name)(ansi blue)...(ansi reset)"

    let github_repo_url = if not $github_repo.private {
      $github_repo.html_url
    } else {
      $"https://($github_token)@github.com/($github_repo.full_name)"
    }

    let response = (
      http post $"($forgejo_url)/api/v1/repos/migrate"
      --allow-errors
      -t application/json
      -H [ Authorization $"token ($forgejo_token)" ]
      {
        clone_addr: $github_repo_url
        mirror: ($strategy != "cloned")
        private: $github_repo.private

        repo_owner: $forgejo_user
        repo_name: $github_repo.name
      }
    )

    let error_message = ($response | get -i message)

    if ($error_message != null and $error_message =~ "already exists") {
      print $" (ansi yellow)Already mirrored!(ansi reset)"
    } else if ($error_message != null) {
      print $" (ansi red)Unknown error: ($error_message)(ansi reset)"
    } else {
      print $" (ansi green_bold)Success!(ansi reset)"
    }
  }

  null
}
