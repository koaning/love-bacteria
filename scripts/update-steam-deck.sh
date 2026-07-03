#!/bin/bash
# Build the current commit on GitHub and install its AppImage on the Steam Deck.

set -euo pipefail

repo="koaning/love-bacteria"
workflow="release.yml"
artifact="Sporeline-x86_64.AppImage"
branch="$(git branch --show-current)"
head_sha="$(git rev-parse HEAD)"
remote_sha="$(git ls-remote origin "refs/heads/${branch}" | awk '{print $1}')"

if [ "${remote_sha}" != "${head_sha}" ]; then
  echo "Current commit ${head_sha} is not pushed to origin/${branch}." >&2
  echo "Push the branch before archiving so GitHub can build this revision." >&2
  exit 1
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Starting AppImage build for ${branch}@${head_sha}..."
gh workflow run "${workflow}" --repo "${repo}" --ref "${branch}"

run_id=""
for _ in $(seq 1 30); do
  run_id="$(
    gh run list \
      --repo "${repo}" \
      --workflow "${workflow}" \
      --branch "${branch}" \
      --event workflow_dispatch \
      --limit 10 \
      --json databaseId,headSha,createdAt \
      --jq ".[] | select(.headSha == \"${head_sha}\" and .createdAt >= \"${started_at}\") | .databaseId" \
      | head -1
  )"
  if [ -n "${run_id}" ]; then
    break
  fi
  sleep 2
done

if [ -z "${run_id}" ]; then
  echo "Could not find the GitHub Actions run for ${head_sha}." >&2
  exit 1
fi

gh run watch "${run_id}" --repo "${repo}" --exit-status

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
gh run download "${run_id}" \
  --repo "${repo}" \
  --name "${artifact}" \
  --dir "${tmp_dir}"

remote_tmp="Applications/.${artifact}.$$"
ssh -o BatchMode=yes -o ConnectTimeout=10 steamdeck 'mkdir -p "$HOME/Applications"'
scp \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "${tmp_dir}/${artifact}" \
  "steamdeck:${remote_tmp}"

echo "Installing ${artifact} on steamdeck..."
ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  steamdeck \
  "install -m 0755 \"\$HOME/${remote_tmp}\" \"\$HOME/Applications/${artifact}\" && rm -f \"\$HOME/${remote_tmp}\""
