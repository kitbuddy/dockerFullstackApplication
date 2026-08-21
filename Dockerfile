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

######### Stage 3: Production runtime (JRE only) #########
FROM eclipse-temurin:17-jre-jammy
LABEL stage=runtime

# Create non-root user
RUN useradd -m appuser && mkdir /app && chown appuser:appuser /app
USER appuser
WORKDIR /app

# Copy the fat jar from the maven-builder
COPY --from=maven-builder --chown=appuser:appuser /app/backend/target/*.jar ./app.jar

EXPOSE 8080
ENV JAVA_OPTS "-Xms256m -Xmx512m -Dspring.profiles.active=prod"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
