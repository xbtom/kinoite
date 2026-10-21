#!/bin/bash

# Helpers that keep the build steps from failing on transient network problems:
# DNS hiccups, flaky mirrors, rate limiting, 5xx errors and stalled transfers.
#
# This file is meant to be sourced by the step scripts, not executed. It only
# defines functions and has no side effects. Anything fetched from an external
# server should go through these helpers instead of calling `curl` or
# `git clone` directly, so that one bad moment on a third-party host cannot
# fail the whole image build.
#
# Tunables (environment variables, read on every call):
#   NETWORK_ATTEMPTS      total attempts per operation   (default: 5)
#   NETWORK_RETRY_DELAY   seconds between two attempts   (default: 10)
#
# Responsibility: retry network fetches only.

# git, but a transfer that stays below 1 KB/s for 60 s is aborted (and then
# retried by the callers below) instead of hanging until the CI job times out.
git_net() {
    git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"
}

# Called after a failed attempt: waits before the next one, or returns 1 once
# all attempts are used up.
#
# Usage: _backoff ATTEMPT DESCRIPTION
_backoff() {
    local attempt="$1" what="$2"
    local attempts="${NETWORK_ATTEMPTS:-5}" delay="${NETWORK_RETRY_DELAY:-10}"

    if ((attempt >= attempts)); then
        echo "ERROR: ${what} failed after ${attempts} attempts." >&2
        return 1
    fi
    echo "WARNING: ${what} failed (attempt ${attempt}/${attempts}); retrying in ${delay}s..." >&2
    sleep "${delay}"
}

# fetch URL OUTPUT_FILE [CURL_OPTION...]
#
# Downloads URL to OUTPUT_FILE and fails if it cannot. HTTP errors (4xx/5xx)
# are failures instead of error pages saved as if they were the file, and
# nothing is left behind in OUTPUT_FILE on failure.
#
# By default only transient errors are retried: timeouts, DNS resolution
# failures and HTTP 408/429/5xx. A permanent error such as 404 fails at once,
# so this is also safe for lookups where "not found" is an acceptable answer.
# Pass --retry-all-errors for a download that must exist: it additionally
# survives refused or dropped connections, including one that breaks off
# half-way through a large file.
fetch() {
    local url="$1" output="$2"
    local attempts="${NETWORK_ATTEMPTS:-5}" delay="${NETWORK_RETRY_DELAY:-10}"
    shift 2

    if ! curl --fail --location --no-progress-meter \
        --connect-timeout 20 --speed-limit 1000 --speed-time 60 \
        --retry "$((attempts - 1))" --retry-delay "${delay}" \
        "$@" --output "${output}" "${url}"; then
        rm -f -- "${output}"
        return 1
    fi
}

# git_clone URL DEST [GIT_CLONE_OPTION...]
#
# Clones URL into DEST, retrying on failure. DEST is removed before every
# attempt, so a half-finished clone can never make the next attempt fail, and
# nothing is left behind in DEST if every attempt fails.
git_clone() {
    local url="$1" dest="$2" attempt=1
    shift 2

    until rm -rf -- "${dest:?}" && git_net clone "$@" "${url}" "${dest}"; do
        if ! _backoff "${attempt}" "git clone ${url}"; then
            rm -rf -- "${dest:?}"
            return 1
        fi
        attempt=$((attempt + 1))
    done
}

# git_latest_tag URL
#
# Prints the highest version tag of a remote repository. Retries when the
# remote cannot be queried, and fails (instead of printing an empty string)
# when it cannot be queried at all or has no tags.
git_latest_tag() {
    local url="$1" attempt=1 refs tag

    until refs="$(git_net ls-remote --tags --sort=v:refname "${url}")" &&
        tag="$(printf '%s\n' "${refs}" | grep -v '\^{}' | tail -n 1 | sed 's|.*/||')" &&
        [[ -n "${tag}" ]]; do
        _backoff "${attempt}" "git ls-remote ${url}" || return 1
        attempt=$((attempt + 1))
    done
    printf '%s\n' "${tag}"
}
