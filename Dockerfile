# Multi-stage Dockerfile for Angular frontend + Spring Boot backend
# Assumptions:
# - Angular app is in ./frontend
# - Spring Boot app is in ./backend
# - Angular build outputs to frontend/dist

######### Stage 1: Build Angular frontend #########
FROM node:20-alpine AS node-builder
LABEL stage=frontend-build
WORKDIR /app/frontend

# Install dependencies using package*.json to maximize Docker cache
COPY frontend/package*.json ./
RUN npm ci --silent

# Copy source and build
COPY frontend/ .
RUN npm run build --silent

######### Stage 2: Build Spring Boot backend #########
FROM maven:3.9.4-eclipse-temurin-17 AS maven-builder
LABEL stage=backend-build
WORKDIR /app/backend

# Copy pom.xml first to leverage Docker cache for dependencies
COPY backend/pom.xml ./
# If you have a parent pom or multi-module root pom, copy it here too (adjust path)
# Copy only what is necessary to fetch dependencies
RUN mvn -B -f pom.xml dependency:go-offline || true

# Copy backend source
COPY backend/ .

# Copy built frontend static artifacts into Spring Boot static resources
# Adjust destination if your Spring app serves static files from a different location
COPY --from=node-builder /app/frontend/dist /app/backend/src/main/resources/static

# Build the Spring Boot application (skip tests in Docker build for speed)
RUN mvn -B -f pom.xml clean package -DskipTests

######### Stage 3: Runtime: Tomcat (WAR deployment) #########
FROM tomcat:10.1-jdk17-temurin
LABEL stage=runtime

# Clean default webapps directory and deploy application as ROOT.war
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy the built WAR into Tomcat webapps as ROOT.war
COPY --from=maven-builder /app/backend/target/*.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080
# JVM options for Tomcat
ENV CATALINA_OPTS "-Xms256m -Xmx512m -Dspring.profiles.active=prod"

# Use Tomcat's default entrypoint which starts catalina
CMD ["catalina.sh", "run"]
