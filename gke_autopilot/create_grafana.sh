#export SQL_REGION=
#export SQL_INSTANCE=

#DB 시크릿 지정
kubectl create secret generic ${SVC_PROJECT}-gke-${SVC_NAME}-secret \
  --from-literal=database=**** \
  --from-literal=user=**** \
  --from-literal=password=**** \
  -n ${K8S_NAMESPACE}

export GRAFANA_TAG=12.0.0
export ENV=prd

curl -s https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/refs/heads/main/examples/grafana.yaml |
sed -E "s|(image:\s*grafana/grafana:).*|\1${GRAFANA_TAG}|" |
awk -v prj="${SVC_PROJECT}" \
    -v svc="${SVC_NAME}" \
    -v sql="${SQL_REGION}:${SQL_INSTANCE}" \
    -v env="${ENV}" '
BEGIN {
  use_sql = (sql != ":") ? 1 : 0
}

$0 ~ /^kind:[[:space:]]*Deployment/ {
  in_deployment = 1
}
in_deployment && /^metadata:/ {
  print
  print "  labels:"
  print "    app: grafana"
  print "    env: \"" env "\""
  print "    service: \"" svc "\""
  in_deployment = 0
  next
}

$0 ~ /^ *template:/ {
  in_pod = 1
}

in_pod && /^[[:space:]]+labels:/ {
  print
  match($0, /^[[:space:]]+/)
  indent = substr($0, RSTART, RLENGTH)
  print indent "  app: grafana"
  print indent "  env: \"" env "\""
  print indent "  service: \"" svc "\""
  skip_app_label = 1
  next
}

in_pod && /app: grafana/ && skip_app_label == 1 {
  skip_app_label = 0
  next
}

$0 ~ /kind:[[:space:]]*Service/ {
  in_svc = 1
  svc_metadata = 1
}

svc_metadata && /^metadata:/ {
  print
  next
}

svc_metadata && /^  name:/ {
  print
  print "  annotations:"
  print "    cloud.google.com/neg: '\''{\"exposed_ports\": {\"80\": {\"name\": \"" prj "-" svc "-neg" "\"}}}'\''"
  svc_metadata = 0
  next
}

in_pod && /containers:/ {
  print "      serviceAccountName: " prj "-gke-" svc "-svc"
  print "      securityContext:"
  print "        fsGroup: 472"
}

in_pod && /containerPort: 3000/ {
  print
  print "        readinessProbe:"
  print "          failureThreshold: 3"
  print "          httpGet:"
  print "            path: /robots.txt"
  print "            port: 3000"
  print "            scheme: HTTP"
  print "          initialDelaySeconds: 20"
  print "          periodSeconds: 30"
  print "        env:"
  print "          - name: GF_METRICS_ENABLED"
  print "            value: \"true\""
  print "          - name: GF_METRICS_ENDPOINT"
  print "            value: \"/metrics\""
  if (use_sql) {
    print "          - name: GF_DATABASE_TYPE"
    print "            value: \"postgres\""
    print "          - name: GF_DATABASE_HOST"
    print "            value: \"127.0.0.1:5432\""
    split("name,user,password", keys, ",")
    for (i = 1; i <= 3; i++) {
      print "          - name: GF_DATABASE_" toupper(keys[i])
      print "            valueFrom:"
      print "              secretKeyRef:"
      print "                name: " svc "-secret"
      print "                key: " keys[i]
    }
  }
  print "        resources:"
  print "          requests:"
  print "            cpu: \"250m\""
  print "            memory: \"512Mi\""
  print "            ephemeral-storage: \"256Mi\""
  print "          limits:"
  print "            cpu: \"500m\""
  print "            memory: \"768Mi\""
  print "            ephemeral-storage: \"512Mi\""
  print "        volumeMounts:"
  print "          - mountPath: /var/lib/grafana"
  print "            name: " prj "-gke-" svc "-pv"
  if (use_sql) {
    print "      - name: cloud-sql-proxy"
    print "        image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.15.3-alpine"
    print "        args:"
    print "          - \"--private-ip\""
    print "          - \"--auto-iam-authn\""
    print "          - \"--structured-logs\""
    print "          - \"--port=5432\""
    print "          - \"" prj ":" sql "\""
    print "        securityContext:"
    print "          runAsNonRoot: true"
    print "        resources:"
    print "          requests:"
    print "            cpu: \"100m\""
    print "            memory: \"128Mi\""
    print "          limits:"
    print "            cpu: \"200m\""
    print "            memory: \"256Mi\""
  }
  print "      volumes:"
  print "        - name: " prj "-gke-" svc "-pv"
  print "          persistentVolumeClaim:"
  print "            claimName: " prj "-gke-" svc "-pvc"
  next
}

# Service 스펙 및 PVC 생성
in_svc && /^spec:/ {
  print "spec:"
  print "  type: ClusterIP"
  print "  selector:"
  print "    app: grafana"
  print "  ports:"
  print "    - port: 80"
  print "      targetPort: 3000"
  print "---"
  print "apiVersion: v1"
  print "kind: PersistentVolumeClaim"
  print "metadata:"
  print "  name: " prj "-gke-" svc "-pvc"
  print "spec:"
  print "  accessModes:"
  print "    - ReadWriteOnce"
  print "  storageClassName: standard-rwo"
  print "  resources:"
  print "    requests:"
  print "      storage: 1Gi"
  while (getline > 0 && NF > 0) {}
  in_svc = 0
  next
}

{ print }
' | tee ${SVC_NAME}.yaml
kubectl apply -n "${K8S_NAMESPACE}" -f ${SVC_NAME}.yaml
