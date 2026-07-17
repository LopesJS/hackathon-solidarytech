


```
├── k8s/
│   ├── base/                 ← Manifestos base (Kustomize)
│   └── overlays/
│       ├── lab/              ← Ajustes para lab (menos réplicas)
│       └── prod/             ← Produção (PDB, resources completos)
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml    ← Valida em PRs
│       ├── terraform-apply.yml   ← Aplica em merge/dispatch
│       └── drift-detection.yml   ← Detecta drift diário
└── argocd/
    ├── projects/             ← AppProject com RBAC
    └── apps/                 ← Applications por serviço
```