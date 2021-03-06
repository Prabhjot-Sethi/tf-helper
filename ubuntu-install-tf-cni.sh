#!/bin/bash

set -ex

TF_REPO=${TF_REPO:-tungstenfabric}
TF_REPO_TAG=${TF_REPO_TAG:-R2011-latest}
MASTER_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+')

cat > /tmp/tf-manifest.yaml << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: tungsten
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: env
  namespace: tungsten
data:
  AAA_MODE: no-auth
  ANALYTICS_API_VIP: ""
  ANALYTICS_NODES: $MASTER_IP
  ANALYTICSDB_NODES: $MASTER_IP
  ANALYTICS_SNMP_NODES: $MASTER_IP
  ANALYTICS_ALARM_NODES: $MASTER_IP
  ANALYTICSDB_ENABLE: "true"
  ANALYTICS_ALARM_ENABLE: "true"
  ANALYTICS_SNMP_ENABLE: "true"
  AUTH_MODE: noauth
  CLOUD_ORCHESTRATOR: kubernetes
  CONFIG_API_VIP: ""
  CONFIG_NODES: $MASTER_IP
  CONFIGDB_NODES: $MASTER_IP
  CONTROL_NODES: $MASTER_IP
  CONTROLLER_NODES: $MASTER_IP
  KUBERNETES_POD_SUBNETS: 10.32.0.0/12
  KUBERNETES_SERVICE_SUBNETS: 10.96.0.0/12
  KUBERNETES_IP_FABRIC_SUBNETS: 10.32.0.0/12
  KUBERNETES_IP_FABRIC_FORWARDING: "false"
  KUBERNETES_IP_FABRIC_SNAT: "true"
  KUBERNETES_PUBLIC_FIP_POOL: ""
  LOG_LEVEL: SYS_NOTICE
  METADATA_PROXY_SECRET: ""
  PHYSICAL_INTERFACE: ""
  RABBITMQ_NODES: $MASTER_IP
  RABBITMQ_NODE_PORT: "5673"
  #VROUTER_GATEWAY: 192.168.122.1
  WEBUI_NODES: $MASTER_IP
  WEBUI_VIP: ""
---
# default params will be set in provisioner environment
apiVersion: v1
kind: ConfigMap
metadata:
  name: defaults-env
  namespace: tungsten
data:
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: configzookeeperenv
  namespace: tungsten
data:
  ZOOKEEPER_NODES: $MASTER_IP
  ZOOKEEPER_PORT: "2181"
  ZOOKEEPER_PORTS: "2888:3888"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodemgr-config
  namespace: tungsten
data:
  DOCKER_HOST: "unix://mnt/docker.sock"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: contrail-analyticsdb-config
  namespace: tungsten
data:
  JVM_EXTRA_OPTS: "-Xms1g -Xmx2g"
  CASSANDRA_SEEDS: $MASTER_IP
  CASSANDRA_CLUSTER_NAME: k8s
  CASSANDRA_START_RPC: "true"
  CASSANDRA_LISTEN_ADDRESS: auto
  CASSANDRA_PORT: "9160"
  CASSANDRA_CQL_PORT: "9042"
  CASSANDRA_SSL_STORAGE_PORT: "7001"
  CASSANDRA_STORAGE_PORT: "7000"
  CASSANDRA_JMX_LOCAL_PORT: "7200"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: contrail-configdb-config
  namespace: tungsten
data:
  JVM_EXTRA_OPTS: "-Xms1g -Xmx2g"
  CASSANDRA_SEEDS: $MASTER_IP
  CASSANDRA_CLUSTER_NAME: ContrailConfigDB
  CASSANDRA_START_RPC: "true"
  CASSANDRA_LISTEN_ADDRESS: auto
  CASSANDRA_PORT: "9161"
  CASSANDRA_CQL_PORT: "9041"
  CASSANDRA_SSL_STORAGE_PORT: "7011"
  CASSANDRA_STORAGE_PORT: "7010"
  CASSANDRA_JMX_LOCAL_PORT: "7201"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-config
  namespace: tungsten
data:
  RABBITMQ_ERLANG_COOKIE: "47EFF3BB-4786-46E0-A5BB-58455B3C2CB4"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-manager-config
  namespace: tungsten
data:
  KUBERNETES_API_SERVER: $MASTER_IP
  KUBERNETES_API_SECURE_PORT: "6443"
  K8S_TOKEN_FILE: "/tmp/serviceaccount/token"

# Containers section
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: config-zookeeper
  namespace: tungsten
  labels:
    app: config-zookeeper
spec:
  selector:
    matchLabels:
      app: config-zookeeper
  template:
    metadata:
      labels:
        app: config-zookeeper
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/configdb"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      containers:
      - name: config-zookeeper
        image: "$TF_REPO/contrail-external-zookeeper:$TF_REPO_TAG"
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: config-database
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/lib/zookeeper
          name: zookeeper-data
        - mountPath: /var/log/zookeeper
          name: zookeeper-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: zookeeper-data
        hostPath:
          path: /var/lib/contrail/config-zookeeper
      - name: zookeeper-logs
        hostPath:
          path: /var/log/contrail/config-zookeeper
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-analyticsdb
  namespace: tungsten
  labels:
    app: contrail-analyticsdb
spec:
  selector:
    matchLabels:
      app: contrail-analyticsdb
  template:
    metadata:
      labels:
        app: contrail-analyticsdb
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/analyticsdb"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: "database"
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: contrail-analyticsdb-config
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
        - mountPath: /host/var/lib
          name: host-var-lib
      containers:
      - name: contrail-analyticsdb-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-analyticsdb-config
        env:
        - name: NODE_TYPE
          value: database
        - name: DATABASE_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-analyticsdb-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-analyticsdb-config
        env:
        - name: NODE_TYPE
          value: database
        - name: DATABASE_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-analyticsdb
        image: "$TF_REPO/contrail-external-cassandra:$TF_REPO_TAG"
        securityContext:
          capabilities:
            add: ["SYS_NICE"]
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: database
        envFrom:
        - configMapRef:
            name: contrail-analyticsdb-config
        volumeMounts:
        - mountPath: /var/lib/cassandra
          name: analyticsdb-data
        - mountPath: /var/log/cassandra
          name: analyticsdb-logs
      - name: contrail-analytics-query-engine
        image: "$TF_REPO/contrail-analytics-query-engine:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: NODE_TYPE
          value: database
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: analyticsdb-data
        hostPath:
          path: /var/lib/contrail/analyticsdb
      - name: analyticsdb-logs
        hostPath:
          path: /var/log/contrail/database
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
      - name: host-var-lib
        hostPath:
          path: /var/lib
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-configdb
  namespace: tungsten
  labels:
    app: contrail-configdb
spec:
  selector:
    matchLabels:
      app: contrail-configdb
  template:
    metadata:
      labels:
        app: contrail-configdb
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/configdb"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      containers:
      - name: contrail-configdb
        image: "$TF_REPO/contrail-external-cassandra:$TF_REPO_TAG"
        securityContext:
          capabilities:
            add: ["SYS_NICE"]
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: config-database
        envFrom:
        - configMapRef:
            name: contrail-configdb-config
        volumeMounts:
        - mountPath: /var/lib/cassandra
          name: configdb-data
        - mountPath: /var/log/cassandra
          name: configdb-logs
      - name: contrail-config-database-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-configdb-config
        env:
        - name: NODE_TYPE
          value: config-database
        - name: CONFIG_DATABASE_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
# todo: there is type Socket in new kubernetes, it is possible to use full
# path:
# hostPath:
#   path: /var/run/docker.sock and
 #   type: Socket
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-config-database-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-configdb-config
        env:
        - name: NODE_TYPE
          value: config-database
        - name: CONFIG_DATABASE_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: configdb-data
        hostPath:
          path: /var/lib/contrail/configdb
      - name: configdb-logs
        hostPath:
          path: /var/log/contrail/config-database
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-analytics
  namespace: tungsten
  labels:
    app: contrail-analytics
spec:
  selector:
    matchLabels:
      app: contrail-analytics
  template:
    metadata:
      labels:
        app: contrail-analytics
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/analytics"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      containers:
      - name: contrail-analytics-api
        image: "$TF_REPO/contrail-analytics-api:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-analytics-collector
        image: "$TF_REPO/contrail-analytics-collector:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-analytics-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: analytics
# todo: there is type Socket in new kubernetes, it is possible to use full
# path:
# hostPath:
#   path: /var/run/docker.sock and
#   type: Socket
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-analytics-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: analytics
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-analytics-snmp
  namespace: tungsten
  labels:
    app: contrail-analytics-snmp
spec:
  selector:
    matchLabels:
      app: contrail-analytics-snmp
  template:
    metadata:
      labels:
        app: contrail-analytics-snmp
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/analytics_snmp"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: "analytics-snmp"
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: contrail-analyticsdb-config
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
        - mountPath: /host/var/lib
          name: host-var-lib
      containers:
      - name: contrail-analytics-snmp-collector
        image: "$TF_REPO/contrail-analytics-snmp-collector:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        env:
        - name: NODE_TYPE
          value: analytics-snmp
      - name: contrail-analytics-snmp-topology
        image: "$TF_REPO/contrail-analytics-snmp-topology:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        env:
        - name: NODE_TYPE
          value: analytics-snmp
      - name: contrail-analytics-snmp-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-analyticsdb-config
        env:
        - name: NODE_TYPE
          value: analytics-snmp
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-analytics-snmp-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: nodemgr-config
        - configMapRef:
            name: contrail-analyticsdb-config
        env:
        - name: NODE_TYPE
          value: analytics-snmp
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: host-var-lib
        hostPath:
          path: /var/lib
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-analytics-alarm
  namespace: tungsten
  labels:
    app: contrail-analytics-alarm
spec:
  selector:
    matchLabels:
      app: contrail-analytics-alarm
  template:
    metadata:
      labels:
        app: contrail-analytics-alarm
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/analytics_alarm"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: "analytics-alarm"
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: contrail-analyticsdb-config
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
        - mountPath: /host/var/lib
          name: host-var-lib
      containers:
      - name: kafka
        image: "$TF_REPO/contrail-external-kafka:$TF_REPO_TAG"
        imagePullPolicy: "IfNotPresent"
        securityContext:
          privileged: true
        env:
        - name: NODE_TYPE
          value: analytics-alarm
        - name: KAFKA_NODES
          value: $MASTER_IP
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/kafka
          name: kafka-logs
      - name: contrail-analytics-alarm-gen
        image: "$TF_REPO/contrail-analytics-alarm-gen:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        env:
        - name: NODE_TYPE
          value: analytics-alarm
      - name: contrail-analytics-alarm-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: contrail-analyticsdb-config
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: analytics-alarm
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-analytics-alarm-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: contrail-analyticsdb-config
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: analytics-alarm
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: host-var-lib
        hostPath:
          path: /var/lib
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
      - name: kafka-logs
        hostPath:
          path: /var/log/contrail/kafka
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-controller-control
  namespace: tungsten
  labels:
    app: contrail-controller-control
spec:
  selector:
    matchLabels:
      app: contrail-controller-control
  template:
    metadata:
      labels:
        app: contrail-controller-control
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/control"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      containers:
      - name: contrail-controller-control
        image: "$TF_REPO/contrail-controller-control-control:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-control-dns
        image: "$TF_REPO/contrail-controller-control-dns:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /etc/contrail
          name: dns-config
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-control-named
        image: "$TF_REPO/contrail-controller-control-named:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /etc/contrail
          name: dns-config
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: control
# todo: there is type Socket in new kubernetes, it is possible to use full
# path:
# hostPath:
#   path: /var/run/docker.sock and
#   type: Socket
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-controller-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: control
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: dns-config
        emptyDir: {}
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-controller-config
  namespace: tungsten
  labels:
    app: contrail-controller-config
spec:
  selector:
    matchLabels:
      app: contrail-controller-config
  template:
    metadata:
      labels:
        app: contrail-controller-config
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/config"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      containers:
      - name: contrail-controller-config-api
        image: "$TF_REPO/contrail-controller-config-api:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-config-devicemgr
        image: "$TF_REPO/contrail-controller-config-devicemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-config-schema
        image: "$TF_REPO/contrail-controller-config-schema:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-config-svcmonitor
        image: "$TF_REPO/contrail-controller-config-svcmonitor:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-config-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: config
        - name: CASSANDRA_CQL_PORT
          value: "9041"
        - name: CASSANDRA_JMX_LOCAL_PORT
          value: "7201"
        - name: CONFIG_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
# todo: there is type Socket in new kubernetes, it is possible to use full
# path:
# hostPath:
#   path: /var/run/docker.sock and
#   type: Socket
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
      - name: contrail-controller-config-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: configzookeeperenv
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: config
        - name: CONFIG_NODEMGR__DEFAULTS__minimum_diskGB
          value: "2"
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-controller-webui
  namespace: tungsten
  labels:
    app: contrail-controller-webui
spec:
  selector:
    matchLabels:
      app: contrail-controller-webui
  template:
    metadata:
      labels:
        app: contrail-controller-webui
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/webui"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      containers:
      - name: contrail-controller-webui-job
        image: "$TF_REPO/contrail-controller-webui-job:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      - name: contrail-controller-webui-web
        image: "$TF_REPO/contrail-controller-webui-web:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: redis
  namespace: tungsten
  labels:
    app: redis
spec:
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/analytics"
                operator: Exists
            - matchExpressions:
              - key: "node-role.opencontrail.org/webui"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      containers:
      - name: redis
        image: "$TF_REPO/contrail-external-redis:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/lib/redis
          name: redis-data
        - mountPath: /var/log/redis
          name: redis-logs
      volumes:
      - name: redis-data
        hostPath:
          path: /var/lib/contrail/redis
      - name: redis-logs
        hostPath:
          path: /var/log/contrail/redis
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rabbitmq
  namespace: tungsten
  labels:
    app: rabbitmq
spec:
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/configdb"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      hostNetwork: true
      containers:
      - name: rabbitmq
        image: "$TF_REPO/contrail-external-rabbitmq:$TF_REPO_TAG"
        imagePullPolicy: ""
        env:
        - name: NODE_TYPE
          value: config-database
        - name: RABBITMQ_LOGS
          value: '/var/log/rabbitmq/rabbitmq.log'
        - name: RABBITMQ_SASL_LOGS
          value: '/var/log/rabbitmq/rabbitmq_sasl.log'
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: rabbitmq-config
        volumeMounts:
        - mountPath: /var/lib/rabbitmq
          name: rabbitmq-data
        - mountPath: /var/log/rabbitmq
          name: rabbitmq-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: rabbitmq-data
        hostPath:
          path: /var/lib/contrail/rabbitmq
      - name: rabbitmq-logs
        hostPath:
          path: /var/log/contrail/rabbitmq
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-kube-manager
  namespace: tungsten
  labels:
    app: contrail-kube-manager
spec:
  selector:
    matchLabels:
      app: contrail-kube-manager
  template:
    metadata:
      labels:
        app: contrail-kube-manager
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/config"
                operator: Exists
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoSchedule
      automountServiceAccountToken: false
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      containers:
      - name: contrail-kube-manager
        image: "$TF_REPO/contrail-kubernetes-kube-manager:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: kube-manager-config
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /tmp/serviceaccount
          name: pod-secret
      imagePullSecrets:
      - name: 
      volumes:
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: pod-secret
        secret:
          secretName: contrail-kube-manager-token
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: contrail-agent
  namespace: tungsten
  labels:
    app: contrail-agent
spec:
  selector:
    matchLabels:
      app: contrail-agent
  template:
    metadata:
      labels:
        app: contrail-agent
    spec:
      #Disable affinity for single node setup
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: "node-role.opencontrail.org/agent"
                operator: Exists
      #Enable tolerations for single node setup
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoSchedule
      automountServiceAccountToken: false
      hostNetwork: true
      initContainers:
      - name: contrail-node-init
        image: "$TF_REPO/contrail-node-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        env:
        - name: CONTRAIL_STATUS_IMAGE
          value: "$TF_REPO/contrail-status:$TF_REPO_TAG"
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /host/usr/bin
          name: host-usr-bin
      - name: contrail-vrouter-kernel-init
        image: "$TF_REPO/contrail-vrouter-kernel-build-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /usr/src
          name: usr-src
        - mountPath: /lib/modules
          name: lib-modules
        - mountPath: /etc/sysconfig/network-scripts
          name: network-scripts
        - mountPath: /host/bin
          name: host-bin
      - name: contrail-kubernetes-cni-init
        image: "$TF_REPO/contrail-kubernetes-cni-init:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        volumeMounts:
        - mountPath: /var/lib/contrail
          name: var-lib-contrail
        - mountPath: /host/etc_cni
          name: etc-cni
        - mountPath: /host/opt_cni_bin
          name: opt-cni-bin
        - mountPath: /host/log_cni
          name: var-log-contrail-cni
        - mountPath: /var/log/contrail
          name: contrail-logs
      containers:
      - name: contrail-vrouter-agent
        image: "$TF_REPO/contrail-vrouter-agent:$TF_REPO_TAG"
        imagePullPolicy: ""
        # TODO: Priveleged mode is requied because w/o it the device /dev/net/tun
        # is not present in the container. The mounting it into container
        # doesnt help because of permissions are not enough syscalls,
        # e.g. https://github.com/Juniper/contrail-controller/blob/master/src/vnsw/agent/contrail/linux/pkt0_interface.cc: 48.
        securityContext:
          privileged: true
        envFrom:
        - configMapRef:
            name: env
        lifecycle:
          preStop:
            exec:
              command: ["/clean-up.sh"]
        volumeMounts:
        - mountPath: /dev
          name: dev
        - mountPath: /etc/sysconfig/network-scripts
          name: network-scripts
        - mountPath: /host/bin
          name: host-bin
        - mountPath: /host/etc
          name: host-etc
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /usr/src
          name: usr-src
        - mountPath: /lib/modules
          name: lib-modules
        - mountPath: /var/lib/contrail
          name: var-lib-contrail
        - mountPath: /var/crashes
          name: var-crashes
        - mountPath: /tmp/serviceaccount
          name: pod-secret
      - name: contrail-agent-nodemgr
        image: "$TF_REPO/contrail-nodemgr:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: vrouter
# todo: there is type Socket in new kubernetes, it is possible to use full
# path:
# hostPath:
#   path: /var/run/docker.sock and
#   type: Socket
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
        - mountPath: /mnt
          name: docker-unix-socket
        - mountPath: /var/lib/contrail/loadbalancer
          name: lb-nodemgr
      - name: contrail-agent-provisioner
        image: "$TF_REPO/contrail-provisioner:$TF_REPO_TAG"
        imagePullPolicy: ""
        envFrom:
        - configMapRef:
            name: env
        - configMapRef:
            name: defaults-env
        - configMapRef:
            name: nodemgr-config
        env:
        - name: NODE_TYPE
          value: vrouter
        volumeMounts:
        - mountPath: /var/log/contrail
          name: contrail-logs
      imagePullSecrets:
      - name: 
      volumes:
      - name: dev
        hostPath:
          path: /dev
      - name: network-scripts
        hostPath:
          path: /etc/sysconfig/network-scripts
      - name: host-bin
        hostPath:
          path: /bin
      - name: host-etc
        hostPath:
          path: /etc
      - name: docker-unix-socket
        hostPath:
          path: /var/run
      - name: pod-secret
        secret:
          secretName: contrail-kube-manager-token
      - name: usr-src
        hostPath:
          path: /usr/src
      - name: lib-modules
        hostPath:
          path: /lib/modules
      - name: var-lib-contrail
        hostPath:
          path: /var/lib/contrail
      - name: var-crashes
        hostPath:
          path: /var/contrail/crashes
      - name: etc-cni
        hostPath:
          path: /etc/cni
      - name: opt-cni-bin
        hostPath:
          path: /opt/cni/bin
      - name: var-log-contrail-cni
        hostPath:
          path: /var/log/contrail/cni
      - name: contrail-logs
        hostPath:
          path: /var/log/contrail
      - name: host-usr-bin
        hostPath:
          path: /usr/bin
      - name: lb-nodemgr
        hostPath:
          path: /var/lib/contrail/loadbalancer
# Meta information section
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: contrail-kube-manager
  namespace: tungsten
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: contrail-kube-manager
  namespace: tungsten
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: contrail-kube-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: contrail-kube-manager
subjects:
- kind: ServiceAccount
  name: contrail-kube-manager
  namespace: tungsten
---
apiVersion: v1
kind: Secret
metadata:
  name: contrail-kube-manager-token
  namespace: tungsten
  annotations:
    kubernetes.io/service-account.name: contrail-kube-manager
type: kubernetes.io/service-account-token
EOF

# since we takeover the physical interface, set global DNS to point to relevant DNS configuration, allowing DNS to resolve via vhost0 interface
sudo sed -i -e "s/#DNS=/DNS=$(ip route get 8.8.8.8 | grep -oP 'via \K\S+')/g" /etc/systemd/resolved.conf
sudo service systemd-resolved restart
systemd-resolve --status

kubectl apply -f /tmp/tf-manifest.yaml

MASTER=$(kubectl get nodes | grep master | awk '{print $1}')

# add labels for master node
kubectl label node $MASTER node-role.opencontrail.org/config=
kubectl label node $MASTER node-role.opencontrail.org/configdb=
kubectl label node $MASTER node-role.opencontrail.org/control=
kubectl label node $MASTER node-role.opencontrail.org/agent=
kubectl label node $MASTER node-role.opencontrail.org/analytics=
kubectl label node $MASTER node-role.opencontrail.org/analytics_alarm=
kubectl label node $MASTER node-role.opencontrail.org/analytics_snmp=
kubectl label node $MASTER node-role.opencontrail.org/analyticsdb=
kubectl label node $MASTER node-role.opencontrail.org/webui=

# taint master node
kubectl taint nodes $MASTER node-role.kubernetes.io/master-
