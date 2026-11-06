
export ECR_URI="<<<Account-id>>>.dkr.ecr.eu-west-2.amazonaws.com"  
export REGION="eu-west-2"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URI"
for svc in web worker result ; do
echo "processing $svc"
docker build -t campus-voting-$svc:latest ./$svc
docker tag campus-voting-$svc:latest $ECR_URI/campus-voting-$svc:latest
docker push $ECR_URI/campus-voting-$svc:latest
done

aws ecs update-service --cluster campus-voting-cluster --region "$REGION" --service campus-voting-worker-service --force-new-deployment
aws ecs update-service --cluster campus-voting-cluster --region "$REGION" --service campus-voting-result-service --force-new-deployment
aws ecs update-service --cluster campus-voting-cluster --region "$REGION" --service campus-voting-web-service --force-new-deployment
