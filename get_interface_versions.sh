#!/usr/bin/env bash

REPO=Questie/Questie
REPO_URL=https://github.com/${REPO}
REPO_API=https://api.github.com/repos/${REPO}
REPO_CONTENT=https://raw.githubusercontent.com/${REPO}

REPO_TAG=$( git ls-remote --tags ${REPO_URL} | cut -f2 | sort -V | tail -n1)
TOC_FILES=$(curl -fsSL "${REPO_API}/contents?ref=${REPO_TAG}" | jq -r '.[].name | select(test("^Questie_.*\\.toc$"))')

for toc in ${TOC_FILES}; do
    curl -fsSL "${REPO_CONTENT}/${REPO_TAG}/$toc" -o "$toc" || (echo "Not present: $toc" && continue)

    interface_number=$(grep -H '^## Interface: ' ${toc} | sed 's#.*Interface: \([0-9]\+\)#\1#g')
    interface_variant=$(echo ${toc} | cut -d '_' -f2 | cut -d '.' -f1)
    rm ${toc}

    printf "found $interface_variant $interface_number\n"

    cp kackla.toc kackla_${interface_variant}.toc
    sed -i "s/\\(## Interface: \\)[0-9]\\+/\\1${interface_number}/g" kackla_${interface_variant}.toc
done
