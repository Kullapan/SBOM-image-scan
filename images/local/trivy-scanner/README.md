# Trivy Scanner Worker Image

Image สำหรับ Ephemeral Scanner Pod/Container ที่ทำงานครบวงจรในตัว (Scan -> SBOM CycloneDX -> Upload -> Poll Token) ภายใต้ **OpenShift Restricted SCC**:

## จุดเด่น
1. **Ultra-Lean Footprint (<100MB):** ใช้ Multi-stage build นำ Trivy binary จาก Official Image มาวางบน `alpine:3.19` พร้อมเครื่องมือจำเป็น (`curl`, `jq`, `ca-certificates`) เพื่อประหยัด Bandwidth และ Pull ได้รวดเร็ว (<5 วินาที)
2. **Restricted SCC 100%:** รันเป็น Non-root user (`USER 10001`), กำหนด Cache Directory ไปที่ `/tmp/trivy-cache` ซึ่งสามารถ Mount ด้วย `emptyDir` ได้บน OpenShift
3. **Self-Contained Execution:** บรรจุ `scan-and-upload.sh` เป็น Default Entrypoint ทำให้ Kubernetes Job บน OpenShift (Phase 3) รันได้ทันทีโดยไม่ต้อง Mount ConfigMap Scripts ภายนอก

## การรันด้วย Docker
```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DTRACK_URL="http://host.docker.internal:8081" \
  -e DTRACK_API_KEY="<api-key>" \
  custom-trivy-scanner:latest "my-app/payment-service:1.0.0"
```
