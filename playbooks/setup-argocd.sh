kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports" : [{"name" : "https", "port": 443, "protocol": "TCP", "nodePort" : 31000 }, {"name" : "http", "port": 80, "protocol": "TCP", "nodePort" : 31001 }]}}'

password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)
argocd login localhost:31000 --insecure --username admin --password $password
argocd account update-password --new-password KFSCloud --insecure --current-password $password

argocd repo add gitlab.com/kfs-mining/cluster/prod --type helm --name prod --enable-oci --username $1 --password $2
argocd repo add gitlab.com/kfs-mining/cluster/dev --type helm --name dev --enable-oci --username CalvinCreator --password glpat-qsrXEpswKGT88_orc4gc
