sudo apt update > /dev/null
sudo apt-get install ca-certificates curl gnupg lsb-release -y > /dev/null
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null > /dev/null
sudo apt-get update > /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io -y > /dev/null
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash > /dev/null
