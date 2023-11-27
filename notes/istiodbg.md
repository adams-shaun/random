# First step maybe unnecessary if you've never built images before, but if erroring in cluster create run this
rm -rf out/

# Create dual-stack capable kind cluster
IP_FAMILY=dual ./prow/integ-suite-kind.sh --manual

# Make sure your VScode go version is < 1.18 (I'm using 1.17)

# Run a test with nocleanup flag set (will leave istio installed on your kind cluster)

## VSCode launch cfg
```json
        {
            "name": "DS Ingress",
            "type": "go",
            "request": "launch",
            "mode": "test",
            "program": "/home/ubuntu/go/src/github.com/aspenmesh/istio-private/tests/integration/dualstack/main_test.go",
            "buildFlags": "-tags=integ",
            "env": {
                "KUBECONFIG": "/home/ubuntu/.kube/config",
            },
            "args": [
                "-test.v",
                "--istio.test.pullpolicy=IfNotPresent",
                "--istio.test.work_dir=/tmp/art",
                "--istio.test.hub=localhost:5000",
                "--istio.test.tag=am-prow-cicd",
                // "--istio.test.tag=istio-testing",
                "--istio.test.skipVM",
                "--istio.test.select=-multicluster,-postsubmit",
                "--test.run=TestIngress",
                "--istio.test.nocleanup",
                ],
            "showLog": true
        },
```

## Or from command line 

```bash
go1.17.13 test -p 1 -v -count=1 -tags=integ -vet=off ./tests/integration/dualstack/... -timeout 30m \
 --istio.test.ci --istio.test.pullpolicy=IfNotPresent --istio.test.work_dir=/tmp/artifacts --istio.test.hub=localhost:5000 --istio.test.tag=am-prow-cicd --istio.test.kube.config=/home/ubuntu/.kube/config "--istio.test.select=-multicluster,-postsubmit" --test.run="TestRouteNames" "--istio.test.nocleanup"
 ```

# Use the vscode debug launcher to launch a local pilot service
```json
        {
            "name": "Launch Discovery DualStack",
            "type": "go",
            "request": "launch",
            "mode": "auto",
            "program": "${workspaceFolder}/pilot/cmd/pilot-discovery/main.go",
            "args": [
                "discovery"
            ],
            "env": {
                "ISTIO_DUAL_STACK": "true",
                "PILOT_USE_ENDPOINT_SLICE": "true",
            }
        },
```

If the above step fails for delve/go version error, you may need to update vscode user settings:
```json
    "go.delveConfig": {
        "debugAdapter": "legacy",
        "useApiV1": false,
        "dlvFlags": [
            "--check-go-version=false" // <-----
        ],
        "dlvLoadConfig": {
            "followPointers": true,
            "maxVariableRecurse": 3,
            "maxStringLen": 400,
            "maxArrayValues": 400,
            "maxStructFields": -1
        }
    },
```

# Find the name of one of the running pods you want to check the listener config of

# Set appropriate breakpoints in listener code (listener_builder.go // buildVirtualInboundListener for instance)

# Run pilot_cli to generate listener config from the local pilot instance
```bash
go run pilot/tools/debug/pilot_cli.go --type lds --proxytag echo-dual-ipv4-v1-d6f7bccfd-sdt6z --pilot localhost:15010
```
This should hopefully drop you into a local debugger and you can use to diagnose issues.
