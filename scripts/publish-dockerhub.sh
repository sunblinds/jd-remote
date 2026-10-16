#!/bin/sh
# 릴리스: Docker Hub(sunblinds/jd-remote)에 버전 태그와 latest 를 함께 올린다.
#
#   scripts/publish-dockerhub.sh 0.7.0
#
# 하는 일
#   1) 작업 트리가 깨끗한지 확인(커밋된 코드만 릴리스)
#   2) git 태그 v0.7.0 을 HEAD 에 만들고 origin 에 push (이미 있으면 같은 커밋인지 확인)
#   3) 커밋된 HEAD 를 git archive 로 NAS 에 보내 빌드(linux/amd64, 이미지에 APP_VERSION=0.7.0)
#   4) 같은 이미지에 0.7.0 / 0.7 / latest 세 이름표를 붙여 모두 push
#      - 0.7.0 : 절대 안 바뀜(고정·되돌리기용)
#      - 0.7   : 0.7.x 중 최신(패치만 따라가기)
#      - latest: 가장 최근 릴리스 — 릴리스할 때마다 '항상' 함께 갱신
#      (1.0 이후에는 MAJOR 태그 '1' 도 함께 올린다)
#
# 사전: NAS 에서 한 번 `docker login -u sunblinds` (Docker Hub 액세스 토큰, Read & Write) — 토큰은 NAS 에만 저장된다.
# 환경변수: SSH_HOST(기본 nas), IMAGE(기본 sunblinds/jd-remote)
set -eu
SSH_HOST=${SSH_HOST:-nas}
IMAGE=${IMAGE:-sunblinds/jd-remote}
VERSION=${1:-}
cd "$(dirname "$0")/.."

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "사용법: $0 <MAJOR.MINOR.PATCH>   예: $0 0.7.0"; exit 1 ;;
esac
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "버전 형식이 아닙니다: $VERSION"; exit 1; }
MAJOR=${VERSION%%.*}; MINOR_FULL=${VERSION%.*}
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then echo "커밋되지 않은 변경이 있습니다. 커밋 후 실행하세요."; exit 1; fi
HEAD_SHA=$(git rev-parse HEAD)
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git rev-list -n1 "$TAG")" = "$HEAD_SHA" ] || { echo "$TAG 가 이미 다른 커밋에 붙어 있습니다. 버전을 올리세요."; exit 1; }
else
  git tag -a "$TAG" -m "jd-remote $VERSION"
fi
git push -q origin "$TAG"

TAGS="$VERSION $MINOR_FULL latest"
[ "$MAJOR" -ge 1 ] && TAGS="$TAGS $MAJOR"
SHORT=$(git rev-parse --short=7 HEAD)
TARGS=""; for t in $TAGS; do TARGS="$TARGS -t $IMAGE:$t"; done

echo "== $IMAGE  [$TAGS]  ($TAG, $SHORT) 빌드 → $SSH_HOST"
git archive --format=tar HEAD Dockerfile requirements.txt app | ssh -o BatchMode=yes "$SSH_HOST" "
  set -e; D=/usr/local/bin/docker; W=\$(mktemp -d); trap 'rm -rf \$W' EXIT
  tar xf - -C \$W
  \$D build --pull --build-arg APP_VERSION=$VERSION $TARGS \
    --label org.opencontainers.image.version=$VERSION \
    --label org.opencontainers.image.revision=$SHORT \
    --label org.opencontainers.image.source=https://github.com/bitsets/jd-remote \$W
  for t in $TAGS; do \$D push $IMAGE:\$t; done
  \$D image inspect $IMAGE:$VERSION --format 'image {{.Id}} {{.Architecture}} version={{index .Config.Labels \"org.opencontainers.image.version\"}}'
"
echo "== 완료: $(for t in $TAGS; do printf 'docker.io/%s:%s  ' "$IMAGE" "$t"; done)"
