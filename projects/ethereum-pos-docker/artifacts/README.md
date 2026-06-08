# artifacts/

L1 devnet 기동 후 생성되는 런타임 artifact 디렉토리입니다.

## 파일 목록

| 파일 | 상태 | 설명 |
|------|------|------|
| `l1-chain-info.json` | 런타임 생성 (gitignore) | 실행 중인 L1 devnet의 상태 스냅샷 |
| `l1-chain-info.example.json` | 커밋 대상 | 파일 구조 및 필드 설명용 예시 |

## 생성 방법

체인이 정상 가동 중일 때 (el_offline=false, finalized epoch > 0):

```bash
pnpm run export:artifact
```

생성된 `l1-chain-info.json`은 L2/L3 Docker 프로젝트의 parent chain 설정으로 사용됩니다.

→ 상세 설명: [docs/ethereum-pos-docker/l1-chain-artifact.md](../../docs/ethereum-pos-docker/l1-chain-artifact.md)
