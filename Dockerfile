ARG VERSION=0
ARG ARCH=0
FROM quay.io/harikube/kube-apiserver:${VERSION}-${ARCH} AS apiserver
FROM quay.io/harikube/kube-controller-manager:${VERSION}-${ARCH} AS controllermanager
FROM registry.k8s.io/kube-scheduler:${VERSION} AS kubescheduler
FROM registry.k8s.io/kube-proxy:${VERSION} AS kubeproxy
FROM --platform=linux/${ARCH} registry.access.redhat.com/ubi9/ubi-micro:latest
LABEL name="HariKube"
LABEL vendor="inspirNation Bt."
LABEL version="1.34.0"
LABEL release="0"
LABEL summary="Kubernetes HariKube Edition"
LABEL description="Kubernetes HariKube edition is a horizontally scalable Kubernetes edition."
LABEL maintainer="richard.kovacs@harikube.com"
COPY LICENSE /licenses/LICENSE
RUN mkdir -p /var/run/kubernetes /etc/kubernetes/pki /tmp
RUN chown -R 65534:0 /var/run/kubernetes /etc/kubernetes /tmp
RUN chmod -R 775 /var/run/kubernetes /etc/kubernetes /tmp
USER 65534
COPY --from=apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=controllermanager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kubescheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubeproxy /usr/local/bin/kube-proxy /kubernetes/kube-proxy