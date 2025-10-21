kube-test-patch:
	@for patch in $$(find -name "kubernetes-*.patch" | sort -n) ; do \
		echo =================== $$patch =================== ; \
		tmpdir=$$(mktemp -d) ; \
		cd $$tmpdir && git clone --depth 1 --branch $$(echo "$$patch" | grep -oE 'v[0-9]\.[0-9]+\.[0-9]+') https://github.com/kubernetes/kubernetes kubernetes ; \
		cd $$tmpdir/kubernetes && git apply $(PWD)/$$patch && git status || exit 1 ; \
		rm -rf $$tmpdir/kubernetes ; \
	done