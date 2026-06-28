# Terraform with AWS

## 프로젝트 개요

서로 다른 요구사항(보안 · 실시간 처리 · 확장성)을 가진 3개 도메인의 클라우드 아키텍처를 100% 코드로 정의해, `terraform apply` 한 번으로 동일한 인프라를 재현할 수 있도록 구축한 프로젝트입니다. 단순 리소스 생성을 넘어 네트워크 격리, 최소 권한 IAM(IRSA), 데이터 암호화, 비용 최적화까지 실무 관점의 설계 결정을 코드에 녹였습니다.

- **프로젝트명**: aws-terraform
- **목표 클라우드**: AWS
- **역할**: 인프라 아키텍처 설계 및 Terraform 구현
- **형태**: 도메인별 독립 실행 가능한 3개 IaC 모듈

---

## Phase 1: 금융 — EKS 기반 고가용성 보안 플랫폼

![아키텍처 다이어그램](/docs/images/finance_eks.jpg)

### 목표
금융 도메인의 높은 가용성과 보안 규제 요건을 인프라 코드로 충족합니다. 다중 AZ로 구성한 3계층 VPC 위에 EKS를 올리고, 데이터 계층을 KMS·Secrets Manager로 보호하는 구조를 구현합니다.

### 핵심 설계

- **3계층 서브넷 격리** — 퍼블릭(ALB/NAT GW), 프라이빗 앱(EKS 노드), 데이터(RDS)를 분리해 RDS는 외부 라우팅이 없는 서브넷에 배치하고, EKS 클러스터 보안 그룹에서만 5432 포트를 허용
- **IRSA 최소 권한** — 노드 전체에 권한을 부여하지 않고, 특정 ServiceAccount(`default/fin-app`)에만 시크릿 조회와 KMS 복호화를 허용해 파드 단위로 권한을 제한
- **이중 암호화** — RDS 저장 데이터와 EKS 쿠버네티스 시크릿(etcd) 모두 동일 KMS 키로 봉투 암호화하고 키 자동 교체를 적용
- **WAF 분리 연결** — WAF WebACL은 Terraform으로 생성하고, Ingress ALB에는 AWS Load Balancer Controller 어노테이션으로 연결해 선언적 구성을 유지

### 시연 역량

- VPC 멀티 AZ 네트워킹과 라우팅 설계 (IGW / NAT / 라우트 테이블)
- EKS 클러스터·관리형 노드 그룹·핵심 애드온 프로비저닝
- OIDC 공급자 등록과 IRSA 신뢰 정책 작성
- KMS 봉투 암호화, Secrets Manager, 계층별 보안 그룹 등 보안 모범사례
- 자동 생성 비밀번호와 외부 시스템 연동을 Terraform 의존성으로 안전하게 연결

---

## Phase 2: 제조 — IoT 센서 실시간 데이터 파이프라인

![아키텍처 다이어그램](/docs/images/deploy_iot.jpg)

### 목표
제조 현장의 설비 센서 데이터를 서버리스 아키텍처로 수집·처리·저장·알림하는 파이프라인을 구축합니다. 트래픽에 반응해 자동으로 확장·축소되는 이벤트 기반 구조를 설계합니다.

### 핵심 설계

- **핫/콜드 스토리지 분리** — 최근 상태 조회는 키 기반 DynamoDB로 빠르게, 원본은 날짜 파티션으로 S3에 적재해 비용과 조회 성능을 동시에 확보
- **버퍼링을 위한 Kinesis** — IoT Core와 Lambda 사이에 스트림을 배치해 순간 트래픽 폭증을 흡수하고, 배치 처리(`batch_size`)로 Lambda 호출을 효율화
- **최소 권한 IAM** — Lambda 실행 역할에 필요한 스트림·테이블·버킷·토픽 ARN만 부여하고, IoT 규칙 역할은 Kinesis PutRecord만 허용
- **변수화된 알림** — 온도 임계치와 알림 이메일을 변수로 분리해 환경별로 다르게 배포 가능

### 시연 역량

- 이벤트 기반 서버리스 파이프라인 설계 (수집 → 스트림 → 처리 → 저장 → 알림)
- IoT Core 토픽 규칙과 Kinesis 연동
- Lambda 패키징 자동화 (`archive_file`)와 이벤트 소스 매핑
- DynamoDB(온디맨드), S3(퍼블릭 액세스 차단), SNS 구독 구성
- 서비스 간 최소 권한 IAM 정책 작성

### 테스트 결과

**메시지 발행**
```powershell
$stream = terraform output -raw kinesis_stream_name
$json = '{"device_id":"press-01","timestamp":1718000000,"temperature":92}'
$data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
aws kinesis put-record --stream-name $stream --partition-key test --data $data
```

- DynamoDB 테이블에 디바이스 상태 정상 적재 확인
- S3에 `press-01-1718000000.json` 원본 데이터 저장 확인
- 임계치(90°C) 초과 시 SNS를 통한 이메일 알림 수신 확인

---

## Phase 3: 커머스 — EKS 기반 MSA

![아키텍처 다이어그램](/docs/images/commerce_eks.jpg)

### 목표
프로모션·세일 시점의 트래픽 급증에 대응하는 확장 가능한 마이크로서비스 아키텍처를 구축합니다. 정적 자산은 CDN으로 오프로딩하고, 동적 API는 컨테이너로 운영하며 부하에 따라 자동 확장되도록 설계합니다.

### 핵심 설계

- **정적/동적 트래픽 분리** — 정적 자산은 CloudFront+S3로 오프로딩해 EKS는 동적 요청에만 집중. S3는 퍼블릭 액세스를 모두 차단하고 OAC로 CloudFront만 읽기 허용
- **2단 오토스케일링 준비** — 노드 그룹에 Cluster Autoscaler 검색 태그를 부여하고, 파드는 HPA로 확장하는 구조를 전제로 IRSA용 OIDC 공급자를 함께 프로비저닝
- **이미지 보안** — ECR에 푸시 시 자동 취약점 스캔(`scan_on_push`)을 적용
- **재사용 가능한 구조** — 네트워크·클러스터·프런트엔드를 파일 단위로 분리해 가독성과 재사용성 확보

### 시연 역량

- EKS 클러스터·노드 그룹·OIDC·핵심 애드온 프로비저닝
- CloudFront + S3 OAC 기반 정적 자산 배포와 버킷 정책 잠금
- ECR 리포지토리와 이미지 스캔 구성
- 쿠버네티스 오토스케일링(HPA / Cluster Autoscaler)을 고려한 인프라 태깅·권한 설계
- EKS 로드밸런서 통합을 위한 서브넷 태깅 등 실무 디테일

### 테스트 결과

- VPC 및 서브넷 네트워크 구성 정상 확인
- CloudFront 배포 및 S3 정적 자산 서빙 확인
- ECR 리포지토리 생성 및 이미지 스캔 동작 확인
- EKS 클러스터 및 노드 그룹 정상 가동 확인

---
