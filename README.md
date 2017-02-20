# ogg

## What does it do
Installs Oracle Goldengate for Oracle Database on an existing Oracle database 

built via https://github.com/mgis-architects/terraform/tree/master/azure/oracleWithOGG

This script only supports Azure currently, mainly due to the disk persistence method

## Pre-req
Staged binaries on Azure File storage in the following directories

* /mnt/software/ogg12201/V100692-01.zip

### Step 1 Prepare ogg4bd build

git clone https://github.com/mgis-architects/ogg

cp ogg-build.ini ~/ogg-build.ini

Modify ~/ogg-build.ini

### Step 2 Execute the script using the Terradata repo 

git clone https://github.com/mgis-architects/terraform

cd azure/ogg

cp ogg-azure.tfvars ~/ogg-azure.tfvars

Modify ~/ogg-azure.tfvars

terraform apply -var-file=~/ogg-azure.tfvars

### Notes
Installation takes up to 35 minutes due to the database
