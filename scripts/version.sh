#!/usr/bin/env bash
# ==============================================================================
# Sirius 统一版本号解析（单一数据源 = git tag）
#
# 规则（按优先级）：
#   1. 环境变量 VERSION（CI 由 git tag 注入，兼容 "v1.2.1" / "1.2.1" 两种写法）
#   2. HEAD 恰好位于某个 tag 上 → 使用该 tag（正式发布构建）
#   3. HEAD 领先最近 tag（或工作区有未提交改动）→ 使用「<最近tag>-dev.<领先提交数>[.dirty]」，
#      避免开发构建覆盖同名正式产物（例如 v1.2.1.dmg 已发布后又被本地 dev 版覆盖）
#   4. 完全没有 git 环境（源码压缩包）→ 回退 FALLBACK_VERSION
# ==============================================================================
FALLBACK_VERSION="1.2.1"

resolve_sirius_version() {
    local root="$1"

    if [ -n "${VERSION:-}" ]; then
        printf '%s' "${VERSION#v}"
        return 0
    fi

    if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        local exact_tag last_tag commits_ahead dirty_suffix

        dirty_suffix=""
        if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
            dirty_suffix=".dirty"
        fi

        exact_tag="$(git -C "$root" describe --exact-match --tags HEAD 2>/dev/null | head -1)"
        if [ -n "$exact_tag" ] && [ -z "$dirty_suffix" ]; then
            printf '%s' "${exact_tag#v}"
            return 0
        fi

        last_tag="$(git -C "$root" describe --tags --abbrev=0 2>/dev/null | head -1)"
        if [ -n "$last_tag" ]; then
            commits_ahead="$(git -C "$root" rev-list --count "${last_tag}..HEAD" 2>/dev/null || echo 0)"
            printf '%s' "${last_tag#v}-dev.${commits_ahead}${dirty_suffix}"
            return 0
        fi
    fi

    printf '%s' "${FALLBACK_VERSION}"
}

resolve_sirius_build_number() {
    local root="$1"

    if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$root" rev-list --count HEAD 2>/dev/null || echo 0
    else
        echo 0
    fi
}
