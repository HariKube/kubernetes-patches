KUBE_PATCH?=required

kube-test-patch:
	echo =================== $(KUBE_PATCH) ===================
	tmpdir=$$(mktemp -d) ; \
	cd $$tmpdir && git clone --depth 1 --branch $$(echo "$(KUBE_PATCH)" | grep -oE 'v[0-9]\.[0-9]+\.[0-9]+') https://github.com/kubernetes/kubernetes kubernetes ; \
	cd $$tmpdir/kubernetes && git apply $(PWD)/$(KUBE_PATCH) && git status || exit 1 ; \
	rm -rf $$tmpdir/kubernetes

kube-test-patch-all:
	@for patch in $$(find -name "kubernetes-*.patch" | sort -n) ; do \
		KUBE_PATCH=$$patch $(MAKE) kube-test-patch ; \
	done
