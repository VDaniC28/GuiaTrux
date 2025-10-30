-- ============================================
-- SCHEMA PARA GEO-GUÍA DE TRANSPORTE PÚBLICO
-- Base de datos: Supabase (PostgreSQL)
-- ============================================

-- Tabla de rutas de transporte
CREATE TABLE transport_routes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    coordinates JSONB NOT NULL, -- Array de {lat, lng}
    distance_km DECIMAL(10, 2),
    estimated_duration_min INTEGER,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índice para búsquedas
CREATE INDEX idx_routes_active ON transport_routes(active);

-- Tabla de empresas de transporte
CREATE TABLE transport_companies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    route_id UUID REFERENCES transport_routes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    route_name VARCHAR(255),
    frequency_min INTEGER DEFAULT 10, -- Frecuencia en minutos
    fare DECIMAL(5,2) DEFAULT 1.50,
    phone VARCHAR(20),
    email VARCHAR(255),
    reliability_score DECIMAL(3,2) DEFAULT 0.75, -- 0 a 1
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para búsquedas eficientes
CREATE INDEX idx_companies_route ON transport_companies(route_id);
CREATE INDEX idx_companies_active ON transport_companies(active);

-- Tabla de paradas de bus
CREATE TABLE bus_stops (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT,
    route_id UUID REFERENCES transport_routes(id) ON DELETE SET NULL,
    is_terminal BOOLEAN DEFAULT false,
    has_shelter BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices geoespaciales
CREATE INDEX idx_stops_location ON bus_stops(latitude, longitude);
CREATE INDEX idx_stops_route ON bus_stops(route_id);

-- Tabla de solicitudes de ruta (historial)
CREATE TABLE route_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    origin_lat DECIMAL(10, 8) NOT NULL,
    origin_lng DECIMAL(11, 8) NOT NULL,
    destination_name VARCHAR(255) NOT NULL,
    destination_lat DECIMAL(10, 8),
    destination_lng DECIMAL(11, 8),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    user_ip VARCHAR(45),
    user_agent TEXT,
    session_id VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para análisis
CREATE INDEX idx_requests_timestamp ON route_requests(timestamp);
CREATE INDEX idx_requests_destination ON route_requests(destination_name);

-- Tabla de resultados de rutas calculadas
CREATE TABLE route_results (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    request_id UUID REFERENCES route_requests(id),
    origin_lat DECIMAL(10, 8) NOT NULL,
    origin_lng DECIMAL(11, 8) NOT NULL,
    destination_lat DECIMAL(10, 8) NOT NULL,
    destination_lng DECIMAL(11, 8) NOT NULL,
    boarding_lat DECIMAL(10, 8) NOT NULL,
    boarding_lng DECIMAL(11, 8) NOT NULL,
    distance_km DECIMAL(10, 2),
    estimated_time_min INTEGER,
    estimated_fare DECIMAL(5, 2),
    confidence_score DECIMAL(3, 2), -- 0 a 1
    selected_route_id UUID REFERENCES transport_routes(id),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para reportes
CREATE INDEX idx_results_timestamp ON route_results(timestamp);
CREATE INDEX idx_results_route ON route_results(selected_route_id);

-- Tabla de reportes generados
CREATE TABLE generated_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    route_result_id UUID REFERENCES route_results(id),
    destination VARCHAR(255),
    report_type VARCHAR(50) DEFAULT 'pdf', -- pdf, json, etc
    file_size_kb INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índice para auditoría
CREATE INDEX idx_reports_timestamp ON generated_reports(timestamp);

-- Tabla de eventos de n8n (logging de integraciones)
CREATE TABLE n8n_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL, -- route_calculated, report_generated, etc
    payload JSONB NOT NULL,
    status VARCHAR(50) DEFAULT 'success', -- success, error, pending
    error_message TEXT,
    processing_time_ms INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para monitoreo
CREATE INDEX idx_events_type ON n8n_events(event_type);
CREATE INDEX idx_events_status ON n8n_events(status);
CREATE INDEX idx_events_timestamp ON n8n_events(timestamp);

-- Tabla de análisis estadísticos
CREATE TABLE route_analytics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    date DATE NOT NULL,
    total_requests INTEGER DEFAULT 0,
    total_successful_routes INTEGER DEFAULT 0,
    avg_distance_km DECIMAL(10, 2),
    avg_estimated_time_min DECIMAL(10, 2),
    avg_fare DECIMAL(5, 2),
    most_popular_destination VARCHAR(255),
    peak_hour INTEGER, -- 0-23
    unique_users INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(date)
);

-- Índice para consultas de análisis
CREATE INDEX idx_analytics_date ON route_analytics(date);

-- Tabla de feedback de usuarios
CREATE TABLE user_feedback (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    route_result_id UUID REFERENCES route_results(id),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    was_route_accurate BOOLEAN,
    actual_fare DECIMAL(5, 2),
    actual_time_min INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índice para análisis de satisfacción
CREATE INDEX idx_feedback_rating ON user_feedback(rating);
CREATE INDEX idx_feedback_route ON user_feedback(route_result_id);

-- ============================================
-- FUNCIONES Y TRIGGERS
-- ============================================

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers para actualizar updated_at
CREATE TRIGGER update_transport_routes_updated_at 
    BEFORE UPDATE ON transport_routes 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transport_companies_updated_at 
    BEFORE UPDATE ON transport_companies 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bus_stops_updated_at 
    BEFORE UPDATE ON bus_stops 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_route_analytics_updated_at 
    BEFORE UPDATE ON route_analytics 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- DATOS DE EJEMPLO (SEED DATA)
-- ============================================

-- Insertar algunas rutas de ejemplo
INSERT INTO transport_routes (name, description, coordinates, distance_km, estimated_duration_min) VALUES
('Ruta A - Centro a Universidad', 'Conecta el centro de Trujillo con la Universidad Nacional', 
 '[
    {"lat": -8.1116, "lng": -79.0288},
    {"lat": -8.1150, "lng": -79.0320},
    {"lat": -8.1180, "lng": -79.0350},
    {"lat": -8.1210, "lng": -79.0380}
 ]'::jsonb, 5.2, 25),

('Ruta B - Mall a Plaza de Armas', 'Desde Mall Aventura Plaza hacia el centro histórico',
 '[
    {"lat": -8.1050, "lng": -79.0250},
    {"lat": -8.1080, "lng": -79.0270},
    {"lat": -8.1110, "lng": -79.0285},
    {"lat": -8.1116, "lng": -79.0288}
 ]'::jsonb, 3.8, 20),

('Ruta C - Terminal a Chan Chan', 'Ruta turística hacia las Huacas',
 '[
    {"lat": -8.1200, "lng": -79.0400},
    {"lat": -8.1150, "lng": -79.0350},
    {"lat": -8.1100, "lng": -79.0300},
    {"lat": -8.1050, "lng": -79.0250}
 ]'::jsonb, 7.5, 35);

-- Insertar empresas de transporte
INSERT INTO transport_companies (route_id, name, route_name, frequency_min, fare, phone, reliability_score) 
SELECT 
    id,
    'Transportes El Sol',
    'Línea A',
    8,
    1.50,
    '044-123456',
    0.92
FROM transport_routes WHERE name = 'Ruta A - Centro a Universidad';

INSERT INTO transport_companies (route_id, name, route_name, frequency_min, fare, phone, reliability_score) 
SELECT 
    id,
    'Express Trujillo',
    'Línea A',
    10,
    1.50,
    '044-234567',
    0.88
FROM transport_routes WHERE name = 'Ruta A - Centro a Universidad';

INSERT INTO transport_companies (route_id, name, route_name, frequency_min, fare, phone, reliability_score) 
SELECT 
    id,
    'Transportes La Libertad',
    'Línea B',
    12,
    2.00,
    '044-345678',
    0.85
FROM transport_routes WHERE name = 'Ruta B - Mall a Plaza de Armas';

INSERT INTO transport_companies (route_id, name, route_name, frequency_min, fare, phone, reliability_score) 
SELECT 
    id,
    'Turismo Moche',
    'Ruta Turística',
    15,
    2.50,
    '044-456789',
    0.90
FROM transport_routes WHERE name = 'Ruta C - Terminal a Chan Chan';

-- Insertar paradas de ejemplo
INSERT INTO bus_stops (name, latitude, longitude, address, route_id, is_terminal) 
SELECT 
    'Terminal Centro',
    -8.1116,
    -79.0288,
    'Av. España 123',
    id,
    true
FROM transport_routes WHERE name = 'Ruta A - Centro a Universidad' LIMIT 1;

INSERT INTO bus_stops (name, latitude, longitude, address, route_id) 
SELECT 
    'Paradero Ovalo Grau',
    -8.1150,
    -79.0320,
    'Av. América Norte',
    id,
    false
FROM transport_routes WHERE name = 'Ruta A - Centro a Universidad' LIMIT 1;

INSERT INTO bus_stops (name, latitude, longitude, address, route_id, is_terminal) 
SELECT 
    'Universidad Nacional',
    -8.1210,
    -79.0380,
    'Av. Juan Pablo II',
    id,
    true
FROM transport_routes WHERE name = 'Ruta A - Centro a Universidad' LIMIT 1;

-- ============================================
-- VISTAS PARA ANÁLISIS
-- ============================================

-- Vista de rutas más populares
CREATE OR REPLACE VIEW v_popular_routes AS
SELECT 
    rr.selected_route_id,
    tr.name as route_name,
    COUNT(*) as times_used,
    AVG(rr.distance_km) as avg_distance,
    AVG(rr.estimated_time_min) as avg_time,
    AVG(rr.estimated_fare) as avg_fare
FROM route_results rr
JOIN transport_routes tr ON rr.selected_route_id = tr.id
GROUP BY rr.selected_route_id, tr.name
ORDER BY times_used DESC;

-- Vista de estadísticas diarias
CREATE OR REPLACE VIEW v_daily_stats AS
SELECT 
    DATE(timestamp) as date,
    COUNT(*) as total_requests,
    AVG(distance_km) as avg_distance,
    AVG(estimated_time_min) as avg_time,
    MIN(estimated_fare) as min_fare,
    MAX(estimated_fare) as max_fare,
    AVG(estimated_fare) as avg_fare
FROM route_results
GROUP BY DATE(timestamp)
ORDER BY date DESC;

-- Vista de empresas mejor valoradas
CREATE OR REPLACE VIEW v_top_companies AS
SELECT 
    tc.name,
    tc.route_name,
    tc.reliability_score,
    tc.fare,
    tc.frequency_min,
    COUNT(DISTINCT rr.id) as routes_served,
    tr.name as route_name_full
FROM transport_companies tc
LEFT JOIN route_results rr ON rr.selected_route_id = tc.route_id
LEFT JOIN transport_routes tr ON tc.route_id = tr.id
WHERE tc.active = true
GROUP BY tc.id, tc.name, tc.route_name, tc.reliability_score, tc.fare, tc.frequency_min, tr.name
ORDER BY tc.reliability_score DESC, routes_served DESC;

-- ============================================
-- POLÍTICAS DE SEGURIDAD (Row Level Security)
-- ============================================

-- Habilitar RLS en tablas sensibles
ALTER TABLE route_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_feedback ENABLE ROW LEVEL SECURITY;

-- Política de lectura pública para rutas y empresas
CREATE POLICY "Public read access for routes" ON transport_routes
    FOR SELECT USING (true);

CREATE POLICY "Public read access for companies" ON transport_companies
    FOR SELECT USING (active = true);

CREATE POLICY "Public read access for bus stops" ON bus_stops
    FOR SELECT USING (true);

-- Política de inserción anónima para solicitudes
CREATE POLICY "Anonymous insert for requests" ON route_requests
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Anonymous insert for results" ON route_results
    FOR INSERT WITH CHECK (true);

-- ============================================
-- COMENTARIOS EN TABLAS
-- ============================================

COMMENT ON TABLE transport_routes IS 'Rutas de transporte público disponibles en Trujillo';
COMMENT ON TABLE transport_companies IS 'Empresas operadoras de transporte público';
COMMENT ON TABLE bus_stops IS 'Paradas y terminales de transporte';
COMMENT ON TABLE route_requests IS 'Historial de solicitudes de ruta de usuarios';
COMMENT ON TABLE route_results IS 'Resultados calculados de rutas con métricas';
COMMENT ON TABLE generated_reports IS 'Registro de reportes PDF generados';
COMMENT ON TABLE n8n_events IS 'Log de eventos procesados por n8n';
COMMENT ON TABLE route_analytics IS 'Análisis estadístico agregado por fecha';
COMMENT ON TABLE user_feedback IS 'Retroalimentación de usuarios sobre rutas';

-- ============================================
-- FIN DEL SCHEMA
-- ============================================