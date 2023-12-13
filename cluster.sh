#!/bin/bash

# Bring the services up
function startServices {
  docker start psqlhms nodemaster node2 node3 jupyter
  sleep 5
  echo ">> Starting hdfs ..."
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/sbin/start-dfs.sh
  sleep 5
  echo ">> Starting yarn ..."
  docker exec -u hadoop -d nodemaster /home/hadoop/hadoop/sbin/start-yarn.sh
  sleep 5
  echo ">> Starting MR-JobHistory Server ..."
  docker exec -u hadoop -d nodemaster /home/hadoop/hadoop/sbin/mr-jobhistory-daemon.sh start historyserver
  sleep 5
  echo ">> Starting Spark ..."
  docker exec -u hadoop -d nodemaster /home/hadoop/spark/sbin/start-master.sh
  docker exec -u hadoop -d node2 /home/hadoop/spark/sbin/start-slave.sh nodemaster:7077
  docker exec -u hadoop -d node3 /home/hadoop/spark/sbin/start-slave.sh nodemaster:7077
  sleep 5
  echo ">> Starting Spark History Server ..."
  docker exec -u hadoop nodemaster /home/hadoop/spark/sbin/start-history-server.sh
  sleep 5
  echo ">> Preparing hdfs for hive ..."
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/bin/hdfs dfs -mkdir -p /tmp
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/bin/hdfs dfs -mkdir -p /user/hive/warehouse
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/bin/hdfs dfs -chmod g+w /tmp
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/bin/hdfs dfs -chmod g+w /user/hive/warehouse
  sleep 5
  echo ">> Starting Hive Metastore ..."
  docker exec -u hadoop -d nodemaster /home/hadoop/hive/bin/hive --service metastore
  docker exec -u hadoop -d nodemaster /home/hadoop/hive/bin/hive --service hiveserver2
  echo ">> Starting Nifi Server ..."
  docker exec -u hadoop -d nifi /home/hadoop/nifi/bin/nifi.sh start
  echo ">> Starting kafka & Zookeeper ..."
  docker exec -u hadoop -d edge /home/hadoop/kafka/bin/zookeeper-server-start.sh -daemon  /home/hadoop/kafka/config/zookeeper.properties
  docker exec -u hadoop -d edge /home/hadoop/kafka/bin/kafka-server-start.sh -daemon  /home/hadoop/kafka/config/server.properties
  echo "Hadoop info @ nodemaster: http://172.20.1.1:8088/cluster"
  echo "DFS Health @ nodemaster : http://172.20.1.1:50070/dfshealth"
  echo "MR-JobHistory Server @ nodemaster : http://172.20.1.1:19888"
  echo "Spark info @ nodemaster  : http://172.20.1.1:8080"
  echo "Spark History Server @ nodemaster : http://172.20.1.1:18080"
  echo "Zookeeper @ edge : http://172.20.1.5:2181"
  echo "Kafka @ edge : http://172.20.1.5:9092"
  echo "Nifi @ edge : http://172.20.1.5:8080/nifi & from host @ http://localhost:8080/nifi"
}
function stopServices {
  echo ">> Stopping Spark Master and slaves ..."
  docker exec -u hadoop -d nodemaster /home/hadoop/hadoop/sbin/stop-master.sh
  docker exec -u hadoop -d node2 /home/hadoop/hadoop/sbin/stop-slave.sh
  docker exec -u hadoop -d node3 /home/hadoop/hadoop/sbin/stop-slave.sh
  docker exec -u hadoop -d nifi /home/hadoop/nifi/bin/nifi.sh stop
  echo ">> Stopping containers ..."
  docker stop nodemaster node2 node3 psqlhms nifi hue edge
}
if [[ $1 = "install" ]]; then
  docker network create --subnet=172.20.0.0/16 hadoopnet # create custom network
  
  # Starting Postresql Hive metastore
  echo ">> Starting postgresql hive metastore ..."
  docker run -d --net hadoopnet --ip 172.20.1.4 --hostname psqlhms --name psqlhms -e POSTGRES_PASSWORD=hive -it ensaradaletai/bigdata_postgres
  sleep 5
  
   # 3 nodes
  echo ">> Starting master and worker nodes ..."
  docker run -d --net hadoopnet --ip 172.20.1.1 -p 8088:8088 -p 8090:8080 -p 50070:50070 --hostname nodemaster --add-host node2:172.20.1.2 --add-host node3:172.20.1.3 --name nodemaster -it ensaradaletai/bigdata_hive:3.1.3
  docker run -d --net hadoopnet --ip 172.20.1.2 --hostname node2 --add-host nodemaster:172.20.1.1 --add-host node3:172.20.1.3  --name node2 -it ensaradaletai/bigdata_spark:3.3.1
  docker run -d --net hadoopnet --ip 172.20.1.3 --hostname node3 --add-host nodemaster:172.20.1.1 --add-host node2:172.20.1.2 --name node3 -it ensaradaletai/bigdata_spark:3.3.1
  docker run -d --net hadoopnet --ip 172.20.1.5 -p 8888:8888 --hostname jupyter --add-host nodemaster:172.20.1.1 --add-host node2:172.20.1.2 --add-host node3:172.20.1.3 --add-host psqlhms:172.20.1.4 --name jupyter -it ensaradaletai/bigdata_jupyter 
  
  # Format nodemaster
  echo ">> Formatting hdfs ..."
  docker exec -u hadoop -it nodemaster /home/hadoop/hadoop/bin/hdfs namenode -format
  startServices
  exit
fi
if [[ $1 = "stop" ]]; then
  stopServices
  exit
fi


if [[ $1 = "uninstall" ]]; then
  stopServices
  docker rmi ensaradaletai/bigdata_hadoop:3.3.5 ensaradaletai/bigdata_spark:3.3.2 ensaradaletai/bigdata_postgres-hms ensaradaletai/bigdata_hive:3.1.3
  docker system prune -f
  exit
fi
if [[ $1 = "start" ]]; then  
  docker start psqlhms nodemaster node2 node3 hue
  startServices
  exit
fi