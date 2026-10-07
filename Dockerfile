# ---- Etapa de construccion ----
# El repositorio no incluye Maven Wrapper (mvnw), por eso se usa una imagen con Maven.
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app

# Copiar primero el pom para cachear las dependencias mientras no cambie
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Copiar el codigo fuente y empaquetar (las pruebas se ejecutan en el job de CI)
COPY src src
RUN mvn -B -q package -DskipTests \
    && cp target/*.jar app.jar

# ---- Etapa de ejecucion ----
# Solo JRE: la imagen final no necesita compilador ni herramientas del JDK
FROM eclipse-temurin:21-jre-alpine

# Seguridad: ejecutar con un usuario sin privilegios (comandos de Alpine/BusyBox)
RUN addgroup -S spring && adduser -S -G spring -H -s /sbin/nologin spring

WORKDIR /app

# Copiar solo el jar ejecutable, propiedad de root y de solo lectura para la app
COPY --from=builder --chown=root:root --chmod=0444 /app/app.jar app.jar

USER spring:spring

EXPOSE 8080

# Alpine no trae curl; wget de BusyBox esta disponible en la imagen base
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
