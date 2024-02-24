# Use the Certbot image as the base image
FROM nginx:latest

# INSTALL DEPENDENCIES
RUN apt update 
RUN apt install -y certbot python3-certbot-nginx curl zip awscli

# Set up your entrypoint script
COPY entrypoint.sh entrypoint.sh
RUN chmod +x ./entrypoint.sh

# # Set the entrypoint script
CMD [ "sh", "entrypoint.sh" ]  
