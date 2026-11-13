#!/usr/bin/env bash
git status --short
if [[ "$(realpath "$0")" == "/e/pixel_world/_lead_git_status.sh" ]]; then
	rm -- "$0"
fi
