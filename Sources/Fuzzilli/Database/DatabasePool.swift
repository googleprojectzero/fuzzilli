import Foundation
import PostgresNIO
import PostgresKit
import NIOPosix
import Logging

/// Manages PostgreSQL connection pooling for efficient database access
public class DatabasePool {
    private let logger: Logging.Logger
    private var eventLoopGroup: EventLoopGroup?
    private var connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>?
    private var isInitialized = false
    private let lock = NSLock()
    
    // Configuration
    private let connectionString: String
    private let maxConnections: Int
    private let connectionTimeout: TimeInterval
    private let retryAttempts: Int
    private let enableLogging: Bool
    private var configuration: SQLPostgresConfiguration?
    
        public init(connectionString: String, maxConnections: Int = 5, connectionTimeout: TimeInterval = 120.0, retryAttempts: Int = 3, enableLogging: Bool = false) {
        self.connectionString = connectionString
        self.maxConnections = maxConnections
        self.connectionTimeout = connectionTimeout
        self.retryAttempts = retryAttempts
        self.enableLogging = enableLogging
        self.logger = Logging.Logger(label: "DatabasePool")
    }
    
    /// Initialize the connection pool
    public func initialize() async throws {
        // Check if already initialized
        let alreadyInitialized = await withLock(lock) { isInitialized }
        
        guard !alreadyInitialized else {
            if enableLogging {
                logger.info("Database pool already initialized")
            }
            return
        }
        
        if enableLogging {
            logger.info("Initializing database connection pool...")
            logger.info("Connection string: \(connectionString)")
            logger.info("Max connections: \(maxConnections)")
            logger.info("Connection timeout: \(connectionTimeout)s")
        }
        
        do {
            // Create event loop group
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            guard let eventLoopGroup = eventLoopGroup else {
                throw DatabasePoolError.initializationFailed("Failed to create event loop group")
            }
            
            // Parse connection string and create configuration
            let config = try parseConnectionString(connectionString)
            self.configuration = config
            
            // Create connection source using the new API
            let connectionSource = PostgresConnectionSource(
                sqlConfiguration: config
            )
            
            // Create connection pool
            connectionPool = EventLoopGroupConnectionPool(
                source: connectionSource,
                maxConnectionsPerEventLoop: maxConnections / System.coreCount,
                logger: logger,
                on: eventLoopGroup
            )
            
            await withLock(lock) {
                isInitialized = true
            }
            
            if enableLogging {
                logger.info("Database connection pool initialized successfully")
            }
            
        } catch {
            logger.error("Failed to initialize database connection pool: \(error)")
            await shutdown()
            throw DatabasePoolError.initializationFailed("Failed to initialize pool: \(error)")
        }
    }
    
    /// Execute an operation with a pooled connection
    public func withConnection<T>(_ operation: @escaping (PostgresConnection) -> EventLoopFuture<T>) async throws -> T {
        guard isInitialized, let pool = connectionPool else {
            throw DatabasePoolError.notInitialized
        }
        
        return try await pool.withConnection(logger: logger) { connection in
            return operation(connection)
        }.get()
    }
    
    /// Test the connection pool by executing a simple query
    public func testConnection() async throws -> Bool {
        do {
            let result = try await withConnection { connection in
                connection.query("SELECT 1 as test", logger: self.logger)
            }
            
            // Check if we got a result
            if result.count > 0 {
                if enableLogging {
                    logger.info("Database connection test successful")
                }
                return true
            } else {
                logger.error("Database connection test failed: no results")
                return false
            }
        } catch {
            logger.error("Database connection test failed: \(error)")
            return false
        }
    }
    
    /// Get connection pool statistics
    public func getPoolStats() async throws -> PoolStats {
        guard isInitialized, let _ = connectionPool else {
            throw DatabasePoolError.notInitialized
        }
        
        // For now, return basic stats
        // TODO: Implement actual pool statistics when PostgresKit supports it
        return PoolStats(
            totalConnections: maxConnections,
            activeConnections: 0, // Not available in current PostgresKit version
            idleConnections: 0,   // Not available in current PostgresKit version
            isHealthy: true
        )
    }
    
    /// Get event loop group for direct connections
    public func getEventLoopGroup() -> EventLoopGroup? {
        return eventLoopGroup
    }
    
    /// Get connection string for direct connections
    public func getConnectionString() -> String {
        return connectionString
    }
    
    /// Get the database configuration
    public func getConfiguration() throws -> SQLPostgresConfiguration {
        guard let config = configuration else {
            throw DatabasePoolError.notInitialized
        }
        return config
    }
    
    /// Shutdown the connection pool
    public func shutdown() async {
        // Use async-safe lock for the check
        let shouldShutdown = await withLock(lock) { isInitialized }
        
        guard shouldShutdown else {
            if enableLogging {
                logger.info("Database pool not initialized, nothing to shutdown")
            }
            return
        }
        
        if enableLogging {
            logger.info("Shutting down database connection pool...")
        }
        
        do {
            // Shutdown connection pool
            if let pool = connectionPool {
                // Use Task.detached to avoid blocking the async context
                Task.detached {
                    pool.shutdown()
                }
                connectionPool = nil
            }
            
            // Shutdown event loop group
            if let eventLoopGroup = eventLoopGroup {
                try await eventLoopGroup.shutdownGracefully()
                self.eventLoopGroup = nil
            }
            
            await withLock(lock) {
                isInitialized = false
            }
            
            if enableLogging {
                logger.info("Database connection pool shutdown complete")
            }
            
        } catch {
            logger.error("Error during database pool shutdown: \(error)")
        }
    }
    
    /// Check if the pool is initialized
    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isInitialized
    }
    
    // MARK: - Private Methods
    
    /// Async-safe locking helper
    private func withLock<T>(_ lock: NSLock, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
    
    private func parseConnectionString(_ connectionString: String) throws -> SQLPostgresConfiguration {
        // Parse postgresql://user:password@host:port/database format
        guard let url = URL(string: connectionString) else {
            throw DatabasePoolError.invalidConnectionString("Invalid connection string format")
        }
        
        guard url.scheme == "postgresql" || url.scheme == "postgres" else {
            throw DatabasePoolError.invalidConnectionString("Invalid scheme, expected postgresql://")
        }
        
        let host = url.host ?? "localhost"
        let port = url.port ?? 5432
        let username = url.user ?? "postgres"
        let password = url.password
        let database = url.path.isEmpty ? nil : String(url.path.dropFirst()) // Remove leading slash
        
        if enableLogging {
            logger.info("Parsed connection: host=\(host), port=\(port), user=\(username), database=\(database ?? "none")")
        }
        
        return SQLPostgresConfiguration(
            hostname: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable // For now, disable TLS - can be made configurable later
        )
    }
}

// MARK: - Supporting Types

/// Connection pool statistics
public struct PoolStats {
    public let totalConnections: Int
    public let activeConnections: Int
    public let idleConnections: Int
    public let isHealthy: Bool
    
    public init(totalConnections: Int, activeConnections: Int, idleConnections: Int, isHealthy: Bool) {
        self.totalConnections = totalConnections
        self.activeConnections = activeConnections
        self.idleConnections = idleConnections
        self.isHealthy = isHealthy
    }
}

/// Database pool errors
public enum DatabasePoolError: Error, LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case invalidConnectionString(String)
    case connectionTimeout
    case poolExhausted
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database pool is not initialized"
        case .initializationFailed(let message):
            return "Failed to initialize database pool: \(message)"
        case .invalidConnectionString(let message):
            return "Invalid connection string: \(message)"
        case .connectionTimeout:
            return "Connection timeout"
        case .poolExhausted:
            return "Connection pool exhausted"
        }
    }
}