export GRAFANA_TAG=11.6.0
#export SQL_REGION=
#export SQL_INSTANCE=

curl -s https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/refs/heads/main/examples/grafana.yaml |
sed -E "s|(image:\s*grafana/grafana:).*|\1${GRAFANA_TAG}|" |
awk -v svc="${SVC_PROJECT}-gke-${SVC_NAME}" \
    -v neg="${SVC_PROJECT}-${SVC_NAME}-neg" \
    -v sql="${SVC_PROJECT}:${SQL_REGION}:${SQL_INSTANCE}" \
    -v prj="${SVC_PROJECT}" '
BEGIN {
  use_sql = (sql != prj "::") ? 1 : 0
}

$0 ~ /kind:[[:space:]]*Service/ {
  in_svc = 1
  svc_metadata = 1
}

svc_metadata && /^metadata:/ {
  print $0
  next
}

svc_metadata && /^  name:/ {
  print $0
  print "  annotations:"
  print "    cloud.google.com/neg: '\''{\"exposed_ports\": {\"80\": {\"name\": \"" neg "\"}}}'\''"
  svc_metadata = 0
  next
}

$template == 0 && /template:/ { in_pod = 1 }

in_pod && /containers:/ {
  print "      serviceAccountName: " svc "-svc"
  print "      securityContext:"
  print "        fsGroup: 472"
}

/containerPort: 3000/ {
  print
  #readinessProbe 추가
  print "        readinessProbe:"
  print "          failureThreshold: 3"
  print "          httpGet:"
  print "            path: /robots.txt"
  print "            port: 3000"
  print "            scheme: HTTP"
  print "          initialDelaySeconds: 20"
  print "          periodSeconds: 30"
  #env 추가
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
  print "            memory: \"768Mi\""
  print "          limits:"
  print "            cpu: \"500m\""
  print "            memory: \"1Gi\""
  #pv mount
  print "        volumeMounts:"
  print "          - mountPath: /var/lib/grafana"
  print "            name: " svc "-pv"  
  # cloud-sql-proxy sidecar(it needs)
  if(use_sql) {
    print "      - name: cloud-sql-proxy"
    print "        image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.15.3-alpine"
    print "        args:"
    print "          - \"--private-ip\""
    print "          - \"--auto-iam-authn\""
    print "          - \"--structured-logs\""
    print "          - \"--port=5432\""
    print "          - \"" sql "\""
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
  #pvc claim
  print "      volumes:"
  print "        - name: " svc "-pv"
  print "          persistentVolumeClaim:"
  print "            claimName: " svc "-pvc"
  next
}
# Service
in_svc && /^spec:/ {
  print "spec:"
  print "  type: LoadBalancer"
  print "  selector:"
  print "    app: grafana"
  print "  ports:"
  print "    - port: 80"
  print "      targetPort: 3000"
  print "---"
  print "apiVersion: v1"
  print "kind: PersistentVolumeClaim"
  print "metadata:"
  print "  name: " svc "-pvc"
  print "spec:"
  print "  accessModes:"
  print "    - ReadWriteOnce"
  print "  storageClassName: standard"
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
