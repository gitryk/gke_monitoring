export SVC_PROJECT=
export SVC_NAME=grafana
export K8S_NAMESPACE=monitoring

#메트릭이 수집 가능되게 하기 위해 기본 서비스 계정에 권한 부여
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer" #모니터링 뷰어
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter" #모니터링 측정항목 작성자

#모니터링용 네임스페이스 만들기
kubectl create namespace ${K8S_NAMESPACE}

#지정한 프로젝트에 지정한 이름으로 서비스 어카운트 생성
gcloud iam service-accounts create ${SVC_PROJECT}-gke-${SVC_NAME} --project=${SVC_PROJECT}

#필수 권한 부여
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer" #모니터링 뷰어
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" #서비스 계정 토큰 생성자
  
#SQL 연결 필요시
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client" #Cloud SQL 클라이언트
gcloud projects add-iam-policy-binding ${SVC_PROJECT} \
  --member="serviceAccount:${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader" #Artifact registry 리더(DB-Proxy 이미지 Pull시 필요)

#네임스페이스에 매핑할 k8s용 서비스 어카운트 생성
kubectl create serviceaccount ${SVC_PROJECT}-gke-${SVC_NAME}-svc -n ${K8S_NAMESPACE}

#k8s의 지정 네임스페이스에서 워크로드 아이덴티티 계정으로 쓸 계정을 선언
kubectl annotate serviceaccount ${SVC_PROJECT}-gke-${SVC_NAME}-svc \
  --namespace ${K8S_NAMESPACE} \
  iam.gke.io/gcp-service-account=${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com

#만든 IAM과 K8S 서비스 어카운트를 바인딩
gcloud iam service-accounts add-iam-policy-binding ${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com \
  --project=${SVC_PROJECT} \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${SVC_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${SVC_PROJECT}-gke-${SVC_NAME}-svc]"


#만들어진 계정 확인(Debugging용)
printf "Namespace [ %s ] Account List:\n" "${K8S_NAMESPACE}"
kubectl get serviceaccounts -n ${K8S_NAMESPACE} | grep ${SVC_NAME}

printf "\n[ %s@%s.iam.gserviceaccount.com ] Info:\n" "${SVC_NAME}" "${SVC_PROJECT}"
gcloud projects get-iam-policy ${SVC_PROJECT} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
  
gcloud iam service-accounts get-iam-policy ${SVC_PROJECT}-gke-${SVC_NAME}@${SVC_PROJECT}.iam.gserviceaccount.com \
  --project=${SVC_PROJECT} \
  --format="table(bindings.role, bindings.members)"
