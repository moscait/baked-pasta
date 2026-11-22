package com.example.demo;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.channels.AsynchronousServerSocketChannel;
import java.nio.channels.AsynchronousSocketChannel;
import java.util.concurrent.ExecutionException;

import org.openziti.Ziti;
import org.openziti.ZitiAddress;
import org.openziti.ZitiContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.server.context.WebServerInitializedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import jakarta.annotation.PreDestroy;

/**
 * Makes the app reachable only over the OpenZiti overlay.
 *
 * <p>Tomcat listens on the container's loopback interface only ({@code server.address=127.0.0.1}),
 * so nothing on the container network or the host can reach it. This bean binds the Ziti service
 * with the embedded SDK and copies each overlay connection to that loopback listener. The service
 * is "dark": it has no reachable port, and only identities with a Dial policy can connect.
 *
 * <p>Active only when {@code ziti.id} is set, so tests and plain local runs need no identity.
 */
@Component
@ConditionalOnProperty("ziti.id")
public class ZitiServiceBridge {

    private static final Logger log = LoggerFactory.getLogger(ZitiServiceBridge.class);
    private static final long SERVICE_TIMEOUT_MS = 10_000;
    private static final int BUFFER_SIZE = 16 * 1024;

    private final File identityFile;
    private final String serviceName;

    private volatile ZitiContext ziti;
    private volatile AsynchronousServerSocketChannel server;

    public ZitiServiceBridge(@Value("${ziti.id}") String identityFile,
                             @Value("${ziti.serviceName}") String serviceName) {
        this.identityFile = new File(identityFile);
        this.serviceName = serviceName;
    }

    /**
     * Binds the service once Tomcat is listening. A failure here fails application startup, so a
     * missing identity or service is reported immediately instead of leaving an unreachable app.
     */
    @EventListener
    public void onWebServerReady(WebServerInitializedEvent event) throws IOException {
        if (!identityFile.isFile()) {
            throw new IllegalStateException("OpenZiti identity file not found: " + identityFile);
        }
        int localPort = event.getWebServer().getPort();

        ziti = Ziti.newContext(identityFile, new char[0]);
        if (ziti.getService(serviceName, SERVICE_TIMEOUT_MS) == null) {
            throw new IllegalStateException("OpenZiti service '" + serviceName + "' is not available to "
                    + identityFile.getName() + " (check its Bind policy)");
        }
        server = ziti.openServer();
        server.bind(new ZitiAddress.Bind(serviceName));
        log.info("Bound OpenZiti service '{}'; forwarding overlay connections to 127.0.0.1:{}",
                serviceName, localPort);

        Thread.ofVirtual().name("ziti-accept").start(() -> acceptLoop(localPort));
    }

    private void acceptLoop(int localPort) {
        while (server != null && server.isOpen()) {
            try {
                AsynchronousSocketChannel client = server.accept().get();
                Thread.ofVirtual().name("ziti-conn").start(() -> forward(client, localPort));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (ExecutionException e) {
                if (server != null && server.isOpen()) {
                    log.warn("Failed to accept an OpenZiti connection", e.getCause());
                }
            }
        }
    }

    /** Copies bytes in both directions until either side closes. */
    private void forward(AsynchronousSocketChannel client, int localPort) {
        try (client; Socket local = new Socket(InetAddress.getLoopbackAddress(), localPort)) {
            Thread upstream = Thread.ofVirtual().start(() -> copyZitiToLocal(client, local));
            copyLocalToZiti(local, client);
            upstream.join();
        } catch (IOException e) {
            log.debug("OpenZiti connection ended: {}", e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void copyZitiToLocal(AsynchronousSocketChannel from, Socket to) {
        ByteBuffer buffer = ByteBuffer.allocate(BUFFER_SIZE);
        try {
            OutputStream out = to.getOutputStream();
            while (from.read(buffer).get() >= 0) {
                buffer.flip();
                out.write(buffer.array(), 0, buffer.limit());
                out.flush();
                buffer.clear();
            }
            to.shutdownOutput();
        } catch (IOException | ExecutionException e) {
            closeQuietly(to);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void copyLocalToZiti(Socket from, AsynchronousSocketChannel to) {
        byte[] bytes = new byte[BUFFER_SIZE];
        try {
            InputStream in = from.getInputStream();
            int n;
            while ((n = in.read(bytes)) >= 0) {
                ByteBuffer buffer = ByteBuffer.wrap(bytes, 0, n);
                while (buffer.hasRemaining()) {
                    to.write(buffer).get();
                }
            }
            to.shutdownOutput();
        } catch (IOException | ExecutionException e) {
            closeQuietly(to);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void closeQuietly(AutoCloseable closeable) {
        try {
            closeable.close();
        } catch (Exception ignored) {
            // already closing
        }
    }

    @PreDestroy
    void stop() {
        AsynchronousServerSocketChannel s = server;
        server = null;
        if (s != null) {
            closeQuietly(s);
        }
        if (ziti != null) {
            ziti.destroy();
        }
    }
}
