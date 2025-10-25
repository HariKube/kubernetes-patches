ARG VERSION=0
ARG ARCH=0
FROM quay.io/harikube/kube-apiserver:${VERSION}-${ARCH} AS apiserver
FROM quay.io/harikube/kube-controller-manager:${VERSION}-${ARCH} AS controllermanager
FROM quay.io/harikube/kube-scheduler:${VERSION}-${ARCH} AS kubescheduler
FROM quay.io/harikube/kube-proxy:${VERSION}-${ARCH} AS kubeproxy
FROM --platform=linux/${ARCH} busybox:1.37.0-musl
COPY --from=apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=controllermanager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kubescheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubeproxy /usr/local/bin/kube-proxy /kubernetes/kube-proxy