# Build with the project's Maven wrapper (same Maven version as CI), on the same Java LTS line
# as the runtime image.
FROM eclipse-temurin:21.0.13_9-jdk-noble@sha256:bc12ebd88ffa6dda0092940e179365b05aef8d813b867f9df5a1f168c9a44feb AS build
WORKDIR /app

COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -B --no-transfer-progress dependency:go-offline
COPY src src
RUN ./mvnw -B --no-transfer-progress clean package -DskipTests

# Runtime image
FROM eclipse-temurin:21.0.13_9-jdk-ubi10-minimal@sha256:e30ec71cd6bac8b72fb27137e39051d4fa74447b64253a1a6a3dff28ec05043c
WORKDIR /app

# Copy the JAR from the build stage
COPY --from=build /app/target/*.jar app.jar

# Writable heartbeat directory (mounted as a shared volume in the sandbox).
# Run as an unprivileged numeric UID; no root needed at runtime.
RUN mkdir -p /status && chown 1001:0 /status && chmod 775 /status
USER 1001

# Expose the application port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
