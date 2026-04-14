# syntax=docker/dockerfile:1

FROM scratch

LABEL maintainer="gmcouto"

# copy local files
COPY root/ /
