/*
  Proyecto: LogiData S.A.S.  
  Descripción: Creación de tablas base y aplicación de constraints de integridad.
*/

-- 1. Tabla Clientes con validación de zona y tipo_cliente
CREATE TABLE clientes (
    id_cliente VARCHAR(50) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    zona VARCHAR(20) NOT NULL,
    tipo_cliente VARCHAR(50) NOT NULL,
    CONSTRAINT check_zona CHECK (zona IN ('Norte', 'Sur', 'Oriente', 'Occidente', 'Centro')),
    CONSTRAINT check_tipo_cliente CHECK (tipo_cliente IN ('Retail', 'Farmacéutico', 'Supermercado', 'Ecommerce', 'Restaurante'))
);

-- 2. Tabla Catalogo con validación de precio y tipo_entrega
CREATE TABLE catalogo (
    id_producto VARCHAR(50) PRIMARY KEY,
    categoria VARCHAR(50) NOT NULL,
    precio DECIMAL(10, 2) NOT NULL CHECK (precio > 0),
    tipo_entrega VARCHAR(50) NOT NULL,
    CONSTRAINT check_tipo_entrega CHECK (tipo_entrega IN ('Same Day', 'Next Day', 'Programada', 'Express'))
);

-- 3. Tabla Pedidos (Sin cambios, mantiene FKs)
CREATE TABLE pedidos (
    id_pedido VARCHAR(50) PRIMARY KEY,
    id_cliente VARCHAR(50) NOT NULL,
    id_producto VARCHAR(50) NOT NULL,
    fecha TIMESTAMP NOT NULL,
    monto DECIMAL(12, 2) NOT NULL CHECK (monto >= 0),
    estado VARCHAR(20) NOT NULL,
    CONSTRAINT fk_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    CONSTRAINT fk_producto FOREIGN KEY (id_producto) REFERENCES catalogo(id_producto),
    CONSTRAINT check_estado_pedido CHECK (estado IN ('CREADO', 'EN_DESPACHO', 'ENTREGADO', 'CANCELADO'))
);

-- 4. Tabla Entregas (Sin cambios)
CREATE TABLE entregas (
    id_pedido VARCHAR(50) PRIMARY KEY,
    hora_programada TIMESTAMP NOT NULL,
    hora_real TIMESTAMP,
    zona VARCHAR(20) NOT NULL,
    conductor VARCHAR(100),
    vehiculo VARCHAR(50),
    CONSTRAINT fk_pedido_entrega FOREIGN KEY (id_pedido) REFERENCES pedidos(id_pedido)
);