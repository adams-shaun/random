[mv kubebuilder /usr/local/bin/](https://book.kubebuilder.io/quick-start.html)

# download kubebuilder and install locally.
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

kubebuilder init --domain aspenmesh.io

kubebuilder create api --group networking --version v1 --kind ServiceEntry

# edit the serviceentry_types.go
make manifests