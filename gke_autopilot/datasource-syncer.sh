export GRAFANA_API_ENDPOINT=http://${SVC_NAME}.${K8S_NAMESPACE}.svc.cluster.local
export DATASOURCE_UIDS= #대시보드 UID값
export GRAFANA_API_TOKEN= #Grafana 서비스 토큰값
export DATASYNC_VER=v0.16.0-gke.3 #도커 이미지 TAG

curl -s https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/refs/heads/main/cmd/datasource-syncer/datasource-syncer.yaml | \
sed -e "s|\$DATASOURCE_UIDS|${DATASOURCE_UIDS}|g" \
    -e "s|\$GRAFANA_API_ENDPOINT|${GRAFANA_API_ENDPOINT}|g" \
    -e "s|\$GRAFANA_API_TOKEN|${GRAFANA_API_TOKEN}|g" \
    -e "s|\$PROJECT_ID|${SVC_PROJECT}|g" \
    -e "s|gke.gcr.io/prometheus-engine/datasource-syncer:[^ ]*|gke.gcr.io/prometheus-engine/datasource-syncer:${DATASYNC_VER}|" | \
awk -v sa="${SVC_PROJECT}-gke-${SVC_NAME}" '
  $0 ~ /kind: Job/ {
    in_job = 1
    printed_sa = 0
  }

  $0 ~ /kind: CronJob/ {
    in_cron = 1
    printed_sa = 0
  }

  # 공통 serviceAccountName 삽입
  (in_job || in_cron) && /containers:/ && !printed_sa {
    indent = match($0, /containers:/)
    space = substr($0, 1, indent - 1)
    print space "serviceAccountName: " sa "-svc"
    print $0
    printed_sa = 1
    next
  }

  $0 ~ /image: gke.gcr.io\/prometheus-engine\/datasource-syncer:/ {
    print
    indent = match($0, /image:/)
    space = substr($0, 1, indent - 1)
    print space "resources:"
    print space "  requests:"
    print space "    cpu: \"10m\""
    print space "    memory: \"64Mi\""
    print space "  limits:"
    print space "    cpu: \"100m\""
    print space "    memory: \"128Mi\""
    next
  }

  { print }
' | tee datasource-syncer.yaml
kubectl apply -n "${K8S_NAMESPACE}" -f datasource-syncer.yaml
