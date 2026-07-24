ARG VERSION=0
ARG ARCH=0
FROM --platform=linux/$BUILDARCH busybox:latest AS directories
RUN mkdir -p /tmp/rootfs/var/run/kubernetes /tmp/rootfs/etc/kubernetes /tmp/rootfs/tmp
RUN chmod -R 775 /tmp/rootfs/var/run/kubernetes /tmp/rootfs/etc/kubernetes /tmp/rootfs/tmp
FROM quay.io/harikube/kube-apiserver:${VERSION}-${ARCH} AS apiserver
FROM quay.io/harikube/kube-controller-manager:${VERSION}-${ARCH} AS controllermanager
FROM registry.k8s.io/kube-scheduler:${VERSION} AS kubescheduler
FROM registry.k8s.io/kube-proxy:${VERSION} AS kubeproxy

FROM --platform=linux/${ARCH} registry.access.redhat.com/ubi9/ubi-micro:latest

ARG VERSION

LABEL name="HariKube"
LABEL vendor="inspirNation Bt."
LABEL version="${VERSION}"
LABEL release="0"
LABEL summary="Kubernetes HariKube Edition"
LABEL description="Kubernetes HariKube edition is a horizontally scalable Kubernetes edition."
LABEL maintainer="richard.kovacs@harikube.com"
COPY LICENSE /licenses/LICENSE
COPY --from=directories --chown=65534:0 /tmp/rootfs/* /
USER 65534
COPY --from=apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=controllermanager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kubescheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubeproxy /usr/local/bin/kube-proxy /kubernetes/kube-proxy