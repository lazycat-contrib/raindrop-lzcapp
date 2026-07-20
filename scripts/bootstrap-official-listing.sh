#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${LAZYCAT_TOKEN:?LAZYCAT_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

package_id="${PACKAGE_ID:-community.lazycat.app.raindrop}"
version="${VERSION:-0.3.0}"
release_tag="${RELEASE_TAG:-v${version}}"
lpk_asset="${LPK_ASSET:-${package_id}-v${version}.lpk}"
api_base="https://appstore.api.lazycat.cloud/api/v3"
work_dir="${RUNNER_TEMP:-/tmp}/raindrop-official-${GITHUB_RUN_ID:-manual}"

mkdir -p "${work_dir}"
trap 'rm -rf "${work_dir}"' EXIT

safe_message() {
  local response_file="$1"
  local message
  message="$(jq -r '.message // .msg // .error.message // .error.msg // .error // empty' "${response_file}" 2>/dev/null \
    | tr '\r\n' ' ' \
    | cut -c1-512)"
  case "${message,,}" in
    *lcst_*|*"bearer "*|*authorization*|*x-user-token*|*cookie*|*password*|*secret*)
      return
      ;;
  esac
  printf '%s\n' "${message}"
}

require_success_status() {
  local status="$1"
  local response_file="$2"
  local stage="$3"
  if [[ "${status}" -ge 200 && "${status}" -lt 300 ]]; then
    return
  fi
  local message
  message="$(safe_message "${response_file}")"
  if [[ -n "${message}" ]]; then
    printf '::error::%s failed with HTTP %s: %s\n' "${stage}" "${status}" "${message}"
  else
    printf '::error::%s failed with HTTP %s\n' "${stage}" "${status}"
  fi
  exit 1
}

upload_image() {
  local image_path="$1"
  local response_file="${work_dir}/upload-$(basename "${image_path}").json"
  local status
  status="$(curl --silent --show-error \
    --connect-timeout 20 \
    --max-time 180 \
    --output "${response_file}" \
    --write-out '%{http_code}' \
    --header "X-User-Token: ${LAZYCAT_TOKEN}" \
    --cookie "userToken=${LAZYCAT_TOKEN}" \
    --form "file=@${image_path}" \
    "${api_base}/developer/upload")"
  require_success_status "${status}" "${response_file}" "Screenshot upload"
  jq -er '.data.url // .url' "${response_file}"
}

gh release download "${release_tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --pattern "${lpk_asset}" \
  --dir "${work_dir}" \
  --clobber

lpk_path="${work_dir}/${lpk_asset}"
release_digest="$(gh release view "${release_tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --json assets \
  --jq ".assets[] | select(.name == \"${lpk_asset}\") | .digest")"
actual_digest="sha256:$(sha256sum "${lpk_path}" | cut -d ' ' -f 1)"
if [[ -z "${release_digest}" || "${release_digest}" != "${actual_digest}" ]]; then
  printf '::error::Release asset digest verification failed\n'
  exit 1
fi

pc_reader="$(upload_image screenshots/reader-desktop.png)"
pc_article="$(upload_image screenshots/article-desktop.png)"
mobile_reader="$(upload_image screenshots/reader-mobile.png)"
mobile_feed="$(upload_image screenshots/feed-mobile.png)"
mobile_article="$(upload_image screenshots/article-mobile.png)"

lpk_response="${work_dir}/lpk-upload.json"
lpk_status="$(curl --silent --show-error \
  --connect-timeout 20 \
  --max-time 300 \
  --output "${lpk_response}" \
  --write-out '%{http_code}' \
  --header "X-User-Token: ${LAZYCAT_TOKEN}" \
  --cookie "userToken=${LAZYCAT_TOKEN}" \
  --form "file=@${lpk_path}" \
  "${api_base}/developer/app/lpk/upload")"
require_success_status "${lpk_status}" "${lpk_response}" "LPK upload"

version_json="$(jq -cer \
  --arg package_id "${package_id}" \
  --arg version "${version}" \
  --arg expected_sha "${actual_digest#sha256:}" \
  --arg zh_changelog "Raindrop ${version} 首次发布：提供 RSS 订阅、刷新、文章阅读、已读与收藏状态，以及桌面和移动端适配。" \
  --arg en_changelog "Initial Raindrop ${version} release with RSS subscriptions, refresh, article reading, read/star state, and responsive desktop and mobile layouts." \
  '
    (.data // .) as $upload
    | select($upload.package == $package_id)
    | select(($upload.version // $upload.name) == $version)
    | select($upload.sha256 == $expected_sha)
    | {
        package: $upload.package,
        name: ($upload.version // $upload.name),
        icon_path: $upload.iconPath,
        pkg_path: $upload.url,
        pkg_hash: $upload.sha256,
        unsupported_platforms: ($upload.unsupportedPlatforms // []),
        min_os_version: $upload.minOsVersion,
        lpk_size: $upload.lpkSize,
        image_size: $upload.imageSize,
        changelogs: {
          zh: $zh_changelog,
          en: $en_changelog
        }
      }
  ' "${lpk_response}")"

review_body="${work_dir}/review.json"
jq -n \
  --arg package_id "${package_id}" \
  --arg pc_reader "${pc_reader}" \
  --arg pc_article "${pc_article}" \
  --arg mobile_reader "${mobile_reader}" \
  --arg mobile_feed "${mobile_feed}" \
  --arg mobile_article "${mobile_article}" \
  --argjson version "${version_json}" \
  '{
    infos: [
      {
        id: 0,
        language: "zh",
        package: $package_id,
        name: "Raindrop",
        brief: "专注阅读体验的自托管多用户 RSS 阅读器",
        description: "Raindrop 支持 RSS 订阅、手动与后台刷新、文章列表和正文阅读、已读状态与收藏状态，并针对桌面端和移动端提供响应式界面。数据保存在用户自己的懒猫微服中。",
        keywords: "RSS,阅读器,订阅,自托管,稍后读",
        source: "https://github.com/ca-x/raindrop",
        source_author: "ca-x",
        support_pc: true,
        support_mobile: true,
        screenshot_pc_paths: [$pc_reader, $pc_article],
        screenshot_mobile_paths: [$mobile_reader, $mobile_feed, $mobile_article]
      },
      {
        id: 0,
        language: "en",
        package: $package_id,
        name: "Raindrop",
        brief: "A self-hosted multi-user RSS reader focused on reading",
        description: "Raindrop provides RSS subscriptions, manual and background refresh, entry lists and article reading, read and star state, plus responsive desktop and mobile layouts. Data remains on the user’s own LazyCat server.",
        keywords: "RSS,reader,feeds,self-hosted,read later",
        source: "https://github.com/ca-x/raindrop",
        source_author: "ca-x",
        support_pc: true,
        support_mobile: true,
        screenshot_pc_paths: [$pc_reader, $pc_article],
        screenshot_mobile_paths: [$mobile_reader, $mobile_feed, $mobile_article]
      }
    ],
    version: $version
  }' > "${review_body}"

review_response="${work_dir}/review-response.json"
review_status="$(curl --silent --show-error \
  --connect-timeout 20 \
  --max-time 180 \
  --output "${review_response}" \
  --write-out '%{http_code}' \
  --header "X-User-Token: ${LAZYCAT_TOKEN}" \
  --cookie "userToken=${LAZYCAT_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${review_body}" \
  "${api_base}/developer/app/${package_id}/review/create")"
require_success_status "${review_status}" "${review_response}" "Official review submission"

if jq -e 'has("success") and (.success | not)' "${review_response}" >/dev/null 2>&1; then
  message="$(safe_message "${review_response}")"
  printf '::error::Official review submission was rejected: %s\n' "${message:-unknown error}"
  exit 1
fi

printf 'Official Raindrop listing and version %s were submitted for review.\n' "${version}"
