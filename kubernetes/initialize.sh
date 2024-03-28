#!/usr/bin/env sh

# TODO: install kustomize sops ksops
kustomize --enable-alpha-plugins --enable-exec build stackgres/ | kubectl apply --force-conflicts --server-side -f -
kustomize --enable-alpha-plugins --enable-exec build . | kubectl apply -f -
