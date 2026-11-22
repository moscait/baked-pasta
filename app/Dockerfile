FROM eclipse-temurin:25-jdk@sha256:884a2f8692cc1e2c7e21f95914adf0ae0eafee9a7eb663a12169cc44468256ec AS build

ENV HOME=/app
RUN mkdir -p $HOME
WORKDIR $HOME
COPY . $HOME
RUN chmod +x ./mvnw && ./mvnw clean package -DskipTests

FROM eclipse-temurin:25-jre-alpine@sha256:e1898fd6a11fc965a994d8ace186fd3585aeb636cf8f05f47a723fcfee0b0918
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring
COPY --from=build --chown=spring:spring /app/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar", "--spring.profiles.active=prod"]
