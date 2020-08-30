# weaviate-kustomize

Intended to run a minimal [weaviate](https://github.com/semi-technologies/weaviate) setup in a local [KIND](https://kind.sigs.k8s.io/) cluster.

Instructions to run & apply to the KIND cluster:
```
kustomize build > out.yaml
kubectl apply -f out.yaml
```

Use `port-forward` to interact with the weaviate API:
```
kubectl port-forward service/weaviate 5432:80
```
This will make the weaviate API accessible on `localhost:5432`. You can e.g. verify with your browser:
```
http://127.0.0.1:5432/v1/
```
