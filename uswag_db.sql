-- =====================================================================================
-- USWAG: Unified System for Work and Growth
-- Final database for MySQL 8.0.16+ / MariaDB 10.5+ (InnoDB). Proponents: Bryan Jay M. Lumabas and Claire Pillo.
-- Import: mysql -uroot < uswag_db.sql, or HeidiSQL > Run SQL file. This script drops and recreates uswag_db.
-- Design rule: the database enforces every business rule itself. Any frontend or backend can be replaced,
-- as long as it only calls the procedures and views below.
--
-- Account  : sp_register_account > sp_get_login > sp_login_ok / sp_login_failed > sp_set_token / sp_check_token
-- Inventory: sp_record_inventory (Pending Review) > sp_verify_inventory (stock changes only here)
-- Sale     : sp_create_sale > sp_add_sale_item (price read from Products) > sp_finalize_sale (credit capital, issue receipt)
-- Contact  : sp_submit_contact_message > sp_review_contact_message; the sender reads sp_get_contact_status
-- =====================================================================================
DROP DATABASE IF EXISTS uswag_db;
CREATE DATABASE uswag_db CHARACTER SET utf8mb4;
USE uswag_db;
-- Allows triggers and procedures to be created when binary logging is on (needs SUPER; skip it if the host blocks it).
SET GLOBAL log_bin_trust_function_creators = 1;
SET NAMES utf8mb4;
-- =====================================================================================
-- SECTION 1: TABLES
-- =====================================================================================

CREATE TABLE IF NOT EXISTS Accounts (
    account_id INT PRIMARY KEY AUTO_INCREMENT,
    role ENUM('Buyer', 'Seller', 'SLP Admin') NOT NULL DEFAULT 'Buyer',
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NULL,   -- optional; unique when set
    contact_number VARCHAR(15) NOT NULL,
    address VARCHAR(150) NULL,
    password_hash VARCHAR(255) NOT NULL,
    api_token_hash CHAR(64) NULL,
    api_token_expires_at DATETIME NULL,
    failed_login_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until DATETIME NULL,
    last_login_at DATETIME NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_account_username UNIQUE (username),
    CONSTRAINT uq_account_email UNIQUE (email),
    CONSTRAINT uq_account_contact UNIQUE (contact_number),
    CONSTRAINT uq_account_token UNIQUE (api_token_hash),
    INDEX idx_accounts_role_active (role, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS Sellers (
    seller_id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    contact_number VARCHAR(15) NULL,
    barangay_zone VARCHAR(50) NOT NULL,
    slp_association VARCHAR(100) DEFAULT 'SLP Community Association',
    join_date DATE DEFAULT (CURRENT_DATE),
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT uq_seller_account UNIQUE (account_id),
    CONSTRAINT uq_seller_contact UNIQUE (contact_number),
    CONSTRAINT fk_sellers_account FOREIGN KEY (account_id) REFERENCES Accounts(account_id) ON DELETE SET NULL,
    INDEX idx_sellers_zone (barangay_zone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS Categories (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- current_stock changes only through triggers on Inventory_Transactions and Sale_Details.
CREATE TABLE IF NOT EXISTS Products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    seller_id INT NOT NULL,
    category_id INT NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    unit_of_measure VARCHAR(20) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    current_stock DECIMAL(10,3) NOT NULL DEFAULT 0.000,
    reorder_level DECIMAL(10,3) NOT NULL DEFAULT 50.000,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT fk_products_seller FOREIGN KEY (seller_id) REFERENCES Sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES Categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT chk_unit_price CHECK (unit_price >= 0.00),
    CONSTRAINT chk_current_stock CHECK (current_stock >= 0.000),
    CONSTRAINT uq_product_seller UNIQUE (product_name, seller_id),
    INDEX idx_products_seller_active (seller_id, is_active),
    INDEX idx_products_category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A sale starts 'Pending'. Moving it to 'Paid' credits capital and issues the receipt.
-- client_id is unique per seller, so offline sales sync without duplicates.
CREATE TABLE IF NOT EXISTS Sales (
    sale_id INT PRIMARY KEY AUTO_INCREMENT,
    seller_id INT NOT NULL,
    buyer_account_id INT NULL,
    sale_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    status ENUM('Paid', 'Pending') NOT NULL DEFAULT 'Pending',
    sync_status ENUM('Online', 'Offline') NOT NULL DEFAULT 'Online',
    client_id CHAR(36) NULL,
    CONSTRAINT fk_sales_seller FOREIGN KEY (seller_id) REFERENCES Sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sales_buyer FOREIGN KEY (buyer_account_id) REFERENCES Accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT uq_sales_seller_client UNIQUE (seller_id, client_id),
    INDEX idx_sales_seller_status (seller_id, status),
    INDEX idx_sales_sync (sync_status, sale_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- unit_price_at_sale is set by a trigger from Products.unit_price; any supplied value is ignored.
CREATE TABLE IF NOT EXISTS Sale_Details (
    sale_detail_id INT PRIMARY KEY AUTO_INCREMENT,
    sale_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity_sold DECIMAL(10,3) NOT NULL,
    unit_price_at_sale DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    line_total DECIMAL(10,2) GENERATED ALWAYS AS (quantity_sold * unit_price_at_sale) STORED,
    CONSTRAINT fk_sd_sale FOREIGN KEY (sale_id) REFERENCES Sales(sale_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sd_product FOREIGN KEY (product_id) REFERENCES Products(product_id) ON DELETE RESTRICT,
    CONSTRAINT chk_qty_sold CHECK (quantity_sold > 0.000),
    CONSTRAINT chk_sale_unit_price CHECK (unit_price_at_sale >= 0.00),
    INDEX idx_saledetails_product (product_id),
    INDEX idx_saledetails_sale (sale_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- quantity is positive, except for an Adjustment, which may be negative.
CREATE TABLE IF NOT EXISTS Inventory_Transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    sale_detail_id INT NULL,
    transaction_type ENUM('Harvest/Restock', 'Sale', 'Spoilage', 'Adjustment') NOT NULL,
    verification_status ENUM('Pending Review', 'Verified', 'Rejected') NOT NULL DEFAULT 'Pending Review',
    quantity DECIMAL(10,3) NOT NULL,
    transaction_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    remarks VARCHAR(150) NULL,
    verified_by_account_id INT NULL,
    verified_at DATETIME NULL,
    CONSTRAINT fk_it_product FOREIGN KEY (product_id) REFERENCES Products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_it_saledetail FOREIGN KEY (sale_detail_id) REFERENCES Sale_Details(sale_detail_id) ON DELETE SET NULL,
    CONSTRAINT fk_it_verifier FOREIGN KEY (verified_by_account_id) REFERENCES Accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT chk_trans_quantity CHECK (quantity <> 0.000),
    INDEX idx_transactions_type (transaction_type),
    INDEX idx_transactions_product (product_id, verification_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS Expenses (
    expense_id INT PRIMARY KEY AUTO_INCREMENT,
    seller_id INT NOT NULL,
    expense_category ENUM('Raw Materials/Seeds', 'Labor', 'Equipment', 'Other') NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    expense_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    description VARCHAR(150) NULL,
    CONSTRAINT fk_expenses_seller FOREIGN KEY (seller_id) REFERENCES Sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT chk_expense_amount CHECK (amount >= 0.00),
    INDEX idx_expenses_seller (seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Changing initial_capital shifts current_balance by the same amount (trigger).
CREATE TABLE IF NOT EXISTS Capital_Management (
    capital_id INT PRIMARY KEY AUTO_INCREMENT,
    seller_id INT NOT NULL,
    initial_capital DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    current_balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_capital_seller FOREIGN KEY (seller_id) REFERENCES Sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT uq_capital_seller UNIQUE (seller_id),
    CONSTRAINT chk_initial_capital CHECK (initial_capital >= 0.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Append-only money trail: triggers block UPDATE and DELETE.
CREATE TABLE IF NOT EXISTS Capital_Ledger (
    ledger_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    seller_id INT NOT NULL,
    entry_type VARCHAR(30) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    balance_after DECIMAL(12,2) NOT NULL,
    reference_id INT NULL,
    note VARCHAR(150) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ledger_seller FOREIGN KEY (seller_id) REFERENCES Sellers(seller_id) ON DELETE RESTRICT,
    INDEX idx_ledger_seller_date (seller_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS Receipts (
    receipt_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sale_id INT NOT NULL,
    account_id INT NULL,
    receipt_number VARCHAR(50) NOT NULL,
    receipt_type ENUM('Online', 'Offline') NOT NULL DEFAULT 'Online',
    receipt_data JSON NOT NULL,
    issued_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_downloaded TINYINT(1) NOT NULL DEFAULT 0,
    sync_status ENUM('Pending', 'Synced') NOT NULL DEFAULT 'Synced',
    CONSTRAINT fk_receipts_sale FOREIGN KEY (sale_id) REFERENCES Sales(sale_id) ON DELETE RESTRICT,
    CONSTRAINT fk_receipts_account FOREIGN KEY (account_id) REFERENCES Accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT uq_receipt_number UNIQUE (receipt_number),
    CONSTRAINT uq_receipt_sale UNIQUE (sale_id),
    INDEX idx_receipts_sync (sync_status, issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Contact messages. status is what the sender sees:
--   'Review' (default, waiting for the SLP Admin) -> 'Received' or 'Rejected' (set with sp_review_contact_message).
-- public_token is a random secret given only to the sender, so only the sender can check the status.
CREATE TABLE IF NOT EXISTS Contact_Messages (
    message_id INT PRIMARY KEY AUTO_INCREMENT,
    sender_name VARCHAR(100) NOT NULL,
    sender_email VARCHAR(100) NULL,
    contact_number VARCHAR(15) NOT NULL,
    subject VARCHAR(50) NOT NULL,
    message_body TEXT NOT NULL,
    status ENUM('Review', 'Received', 'Rejected') NOT NULL DEFAULT 'Review',
    public_token CHAR(32) NOT NULL,
    ip_hash CHAR(64) NULL,
    sms_sent TINYINT(1) NOT NULL DEFAULT 0,
    email_sent TINYINT(1) NOT NULL DEFAULT 0,
    reviewed_by_account_id INT NULL,
    reviewed_at DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_contact_reviewer FOREIGN KEY (reviewed_by_account_id) REFERENCES Accounts(account_id) ON DELETE SET NULL,
    INDEX idx_contact_status (status, created_at),
    INDEX idx_contact_number (contact_number, created_at),
    INDEX idx_contact_ip (ip_hash, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================================
-- SECTION 2: ROUTINES AND TRIGGERS
-- =====================================================================================

DELIMITER //

-- Internal: the only place money moves. It updates the balance and appends to the ledger.
DROP PROCEDURE IF EXISTS sp_capital_move//
CREATE PROCEDURE sp_capital_move(
    IN p_seller_id INT, IN p_amount DECIMAL(12,2), IN p_type VARCHAR(30),
    IN p_ref INT, IN p_note VARCHAR(150))
BEGIN
    DECLARE v_bal DECIMAL(12,2) DEFAULT NULL;
    SELECT current_balance INTO v_bal FROM Capital_Management WHERE seller_id = p_seller_id FOR UPDATE;
    IF v_bal IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capital record missing for this seller.';
    END IF;
    SET v_bal = v_bal + p_amount;
    SET @uswag_ledger_ok = 1;
    UPDATE Capital_Management SET current_balance = v_bal WHERE seller_id = p_seller_id;
    SET @uswag_ledger_ok = 0;
    INSERT INTO Capital_Ledger (seller_id, entry_type, amount, balance_after, reference_id, note)
    VALUES (p_seller_id, p_type, p_amount, v_bal, p_ref, p_note);
END//

-- ---------- Sellers / Capital ----------
DROP TRIGGER IF EXISTS trg_sellers_ai//
CREATE TRIGGER trg_sellers_ai AFTER INSERT ON Sellers FOR EACH ROW
BEGIN
    INSERT INTO Capital_Management (seller_id, initial_capital, current_balance)
    VALUES (NEW.seller_id, 0.00, 0.00);
END//

DROP TRIGGER IF EXISTS trg_capital_bu//
CREATE TRIGGER trg_capital_bu BEFORE UPDATE ON Capital_Management FOR EACH ROW
BEGIN
    IF NEW.seller_id <> OLD.seller_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capital record cannot be reassigned.';
    END IF;
    IF NEW.initial_capital <> OLD.initial_capital THEN
        SET NEW.current_balance = OLD.current_balance + (NEW.initial_capital - OLD.initial_capital);
    ELSEIF NEW.current_balance <> OLD.current_balance AND COALESCE(@uswag_ledger_ok, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Balance can only change through sp_capital_move (ledger-backed).';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_ledger_bu//
CREATE TRIGGER trg_ledger_bu BEFORE UPDATE ON Capital_Ledger FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capital_Ledger is append-only.';
END//

DROP TRIGGER IF EXISTS trg_ledger_bd//
CREATE TRIGGER trg_ledger_bd BEFORE DELETE ON Capital_Ledger FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capital_Ledger is append-only.';
END//

-- ---------- Expenses ----------
DROP TRIGGER IF EXISTS trg_expenses_ai//
CREATE TRIGGER trg_expenses_ai AFTER INSERT ON Expenses FOR EACH ROW
BEGIN
    CALL sp_capital_move(NEW.seller_id, -NEW.amount, 'Expense', NEW.expense_id, NEW.description);
END//

DROP TRIGGER IF EXISTS trg_expenses_bu//
CREATE TRIGGER trg_expenses_bu BEFORE UPDATE ON Expenses FOR EACH ROW
BEGIN
    IF NEW.seller_id <> OLD.seller_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expense cannot be moved to another seller.';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_expenses_au//
CREATE TRIGGER trg_expenses_au AFTER UPDATE ON Expenses FOR EACH ROW
BEGIN
    IF NEW.amount <> OLD.amount THEN
        CALL sp_capital_move(NEW.seller_id, OLD.amount - NEW.amount, 'Expense Adjustment', NEW.expense_id, 'Expense amount edited');
    END IF;
END//

DROP TRIGGER IF EXISTS trg_expenses_ad//
CREATE TRIGGER trg_expenses_ad AFTER DELETE ON Expenses FOR EACH ROW
BEGIN
    CALL sp_capital_move(OLD.seller_id, OLD.amount, 'Expense Reversal', OLD.expense_id, 'Expense deleted');
END//

-- ---------- Products ----------
DROP TRIGGER IF EXISTS trg_products_bi//
CREATE TRIGGER trg_products_bi BEFORE INSERT ON Products FOR EACH ROW
BEGIN
    SET NEW.current_stock = 0.000;
END//

-- ---------- Inventory_Transactions ----------
DROP TRIGGER IF EXISTS trg_it_bi//
CREATE TRIGGER trg_it_bi BEFORE INSERT ON Inventory_Transactions FOR EACH ROW
BEGIN
    DECLARE v_stock DECIMAL(10,3) DEFAULT NULL;
    IF NEW.transaction_type <> 'Adjustment' AND NEW.quantity <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be positive for this transaction type.';
    END IF;
    IF NEW.verification_status = 'Verified' THEN
        SELECT current_stock INTO v_stock FROM Products WHERE product_id = NEW.product_id FOR UPDATE;
        IF v_stock IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product not found.';
        END IF;
        IF NEW.transaction_type IN ('Sale', 'Spoilage') AND v_stock < NEW.quantity THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient inventory stock available.';
        END IF;
        IF NEW.transaction_type = 'Adjustment' AND v_stock + NEW.quantity < 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Adjustment would make stock negative.';
        END IF;
        IF NEW.verified_at IS NULL THEN SET NEW.verified_at = NOW(); END IF;
    END IF;
END//

DROP TRIGGER IF EXISTS trg_it_bu//
CREATE TRIGGER trg_it_bu BEFORE UPDATE ON Inventory_Transactions FOR EACH ROW
BEGIN
    DECLARE v_stock DECIMAL(10,3) DEFAULT NULL;
    IF OLD.verification_status <> 'Pending Review' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reviewed inventory entries are immutable.';
    END IF;
    IF NEW.product_id <> OLD.product_id OR NEW.transaction_type <> OLD.transaction_type
       OR NEW.quantity <> OLD.quantity OR NOT (NEW.sale_detail_id <=> OLD.sale_detail_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only status, remarks and verifier may change on a pending entry.';
    END IF;
    IF NEW.verification_status <> 'Pending Review' THEN
        SET NEW.verified_at = NOW();
    END IF;
    IF NEW.verification_status = 'Verified' THEN
        SELECT current_stock INTO v_stock FROM Products WHERE product_id = NEW.product_id FOR UPDATE;
        IF NEW.transaction_type IN ('Sale', 'Spoilage') AND v_stock < NEW.quantity THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient inventory stock available.';
        END IF;
        IF NEW.transaction_type = 'Adjustment' AND v_stock + NEW.quantity < 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Adjustment would make stock negative.';
        END IF;
    END IF;
END//

DROP TRIGGER IF EXISTS trg_it_ai//
CREATE TRIGGER trg_it_ai AFTER INSERT ON Inventory_Transactions FOR EACH ROW
BEGIN
    IF NEW.verification_status = 'Verified' THEN
        IF NEW.transaction_type IN ('Harvest/Restock', 'Adjustment') THEN
            UPDATE Products SET current_stock = current_stock + NEW.quantity WHERE product_id = NEW.product_id;
        ELSE
            UPDATE Products SET current_stock = current_stock - NEW.quantity WHERE product_id = NEW.product_id;
        END IF;
    END IF;
END//

DROP TRIGGER IF EXISTS trg_it_au//
CREATE TRIGGER trg_it_au AFTER UPDATE ON Inventory_Transactions FOR EACH ROW
BEGIN
    IF OLD.verification_status = 'Pending Review' AND NEW.verification_status = 'Verified' THEN
        IF NEW.transaction_type IN ('Harvest/Restock', 'Adjustment') THEN
            UPDATE Products SET current_stock = current_stock + NEW.quantity WHERE product_id = NEW.product_id;
        ELSE
            UPDATE Products SET current_stock = current_stock - NEW.quantity WHERE product_id = NEW.product_id;
        END IF;
    END IF;
END//

DROP TRIGGER IF EXISTS trg_it_bd//
CREATE TRIGGER trg_it_bd BEFORE DELETE ON Inventory_Transactions FOR EACH ROW
BEGIN
    IF OLD.verification_status = 'Verified' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Verified inventory entries cannot be deleted. Post an Adjustment.';
    END IF;
END//

-- ---------- Sales ----------
DROP TRIGGER IF EXISTS trg_sales_bi//
CREATE TRIGGER trg_sales_bi BEFORE INSERT ON Sales FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sellers WHERE seller_id = NEW.seller_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seller not found or inactive.';
    END IF;
    SET NEW.status = 'Pending';
END//

DROP TRIGGER IF EXISTS trg_sales_bu//
CREATE TRIGGER trg_sales_bu BEFORE UPDATE ON Sales FOR EACH ROW
BEGIN
    IF OLD.status = 'Paid' THEN
        IF NEW.status <> OLD.status OR NEW.seller_id <> OLD.seller_id
           OR NOT (NEW.buyer_account_id <=> OLD.buyer_account_id) OR NEW.sale_date <> OLD.sale_date THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paid sales are immutable (only sync_status may change).';
        END IF;
    ELSE
        IF NEW.seller_id <> OLD.seller_id THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale cannot be reassigned to another seller.';
        END IF;
        IF NEW.status = 'Paid' AND NOT EXISTS (SELECT 1 FROM Sale_Details WHERE sale_id = OLD.sale_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot mark an empty sale as Paid.';
        END IF;
    END IF;
END//

-- Pending -> Paid: credit capital once, issue the receipt with line items.
DROP TRIGGER IF EXISTS trg_sales_au//
CREATE TRIGGER trg_sales_au AFTER UPDATE ON Sales FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;
    IF OLD.status = 'Pending' AND NEW.status = 'Paid' THEN
        SELECT COALESCE(SUM(line_total), 0.00) INTO v_total FROM Sale_Details WHERE sale_id = NEW.sale_id;
        CALL sp_capital_move(NEW.seller_id, v_total, 'Sale', NEW.sale_id, CONCAT('Sale #', NEW.sale_id));
        INSERT INTO Receipts (sale_id, account_id, receipt_number, receipt_type, receipt_data, sync_status)
        SELECT
            NEW.sale_id,
            NEW.buyer_account_id,
            CONCAT('USWAG-', DATE_FORMAT(NEW.sale_date, '%Y%m%d'), '-', LPAD(NEW.sale_id, 5, '0')),
            NEW.sync_status,
            JSON_OBJECT(
                'system', 'USWAG LIVELIHOOD SYSTEM',
                'seller_id', NEW.seller_id,
                'seller_name', (SELECT CONCAT(first_name, ' ', last_name) FROM Sellers WHERE seller_id = NEW.seller_id),
                'sale_id', NEW.sale_id,
                'timestamp', NEW.sale_date,
                'items', (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                              'product', p.product_name, 'unit', p.unit_of_measure,
                              'qty', sd.quantity_sold, 'unit_price', sd.unit_price_at_sale,
                              'line_total', sd.line_total))
                          FROM Sale_Details sd JOIN Products p ON p.product_id = sd.product_id
                          WHERE sd.sale_id = NEW.sale_id),
                'total', v_total,
                'payment_status', 'PAID'
            ),
            IF(NEW.sync_status = 'Offline', 'Pending', 'Synced');
    END IF;
END//

-- Only Pending sales can be deleted; their lines are removed explicitly so stock is restored
-- (FK cascades do not fire triggers in MySQL).
DROP TRIGGER IF EXISTS trg_sales_bd//
CREATE TRIGGER trg_sales_bd BEFORE DELETE ON Sales FOR EACH ROW
BEGIN
    IF OLD.status = 'Paid' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Paid sales cannot be deleted.';
    END IF;
    DELETE FROM Sale_Details WHERE sale_id = OLD.sale_id;
END//

-- ---------- Sale_Details ----------
DROP TRIGGER IF EXISTS trg_sd_bi//
CREATE TRIGGER trg_sd_bi BEFORE INSERT ON Sale_Details FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(10) DEFAULT NULL;
    DECLARE v_sale_seller INT DEFAULT NULL;
    DECLARE v_prod_seller INT DEFAULT NULL;
    DECLARE v_price DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_active TINYINT DEFAULT NULL;
    SELECT status, seller_id INTO v_status, v_sale_seller FROM Sales WHERE sale_id = NEW.sale_id;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale not found.';
    END IF;
    IF v_status = 'Paid' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot add items to a Paid sale.';
    END IF;
    SELECT seller_id, unit_price, is_active INTO v_prod_seller, v_price, v_active
    FROM Products WHERE product_id = NEW.product_id;
    IF v_prod_seller IS NULL OR v_prod_seller <> v_sale_seller THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product does not belong to the selling seller.';
    END IF;
    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product is inactive.';
    END IF;
    SET NEW.unit_price_at_sale = v_price;
END//

DROP TRIGGER IF EXISTS trg_sd_bu//
CREATE TRIGGER trg_sd_bu BEFORE UPDATE ON Sale_Details FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale lines cannot be edited. Delete the line and add it again.';
END//

DROP TRIGGER IF EXISTS trg_sd_bd//
CREATE TRIGGER trg_sd_bd BEFORE DELETE ON Sale_Details FOR EACH ROW
BEGIN
    IF (SELECT status FROM Sales WHERE sale_id = OLD.sale_id) = 'Paid' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lines of a Paid sale cannot be deleted.';
    END IF;
END//

-- Deduct stock (the Inventory trigger rejects it if stock is insufficient, rolling the whole insert back).
DROP TRIGGER IF EXISTS trg_sd_ai//
CREATE TRIGGER trg_sd_ai AFTER INSERT ON Sale_Details FOR EACH ROW
BEGIN
    INSERT INTO Inventory_Transactions
        (product_id, sale_detail_id, transaction_type, verification_status, quantity, remarks)
    VALUES (NEW.product_id, NEW.sale_detail_id, 'Sale', 'Verified', NEW.quantity_sold,
            CONCAT('Auto-deduction for Sale #', NEW.sale_id));
END//

-- Restore stock when a line is removed from a Pending sale.
DROP TRIGGER IF EXISTS trg_sd_ad//
CREATE TRIGGER trg_sd_ad AFTER DELETE ON Sale_Details FOR EACH ROW
BEGIN
    INSERT INTO Inventory_Transactions
        (product_id, sale_detail_id, transaction_type, verification_status, quantity, remarks)
    VALUES (OLD.product_id, NULL, 'Adjustment', 'Verified', OLD.quantity_sold,
            CONCAT('Reversal: line removed from pending Sale #', OLD.sale_id));
END//

-- ---------- Receipts ----------
DROP TRIGGER IF EXISTS trg_receipts_bu//
CREATE TRIGGER trg_receipts_bu BEFORE UPDATE ON Receipts FOR EACH ROW
BEGIN
    IF NEW.sale_id <> OLD.sale_id OR NEW.receipt_number <> OLD.receipt_number
       OR NEW.receipt_type <> OLD.receipt_type OR NOT (NEW.account_id <=> OLD.account_id)
       OR CAST(NEW.receipt_data AS CHAR) <> CAST(OLD.receipt_data AS CHAR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Receipts are immutable (only is_downloaded and sync_status may change).';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_receipts_bd//
CREATE TRIGGER trg_receipts_bd BEFORE DELETE ON Receipts FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Receipts cannot be deleted.';
END//

-- ---------- Application procedures (the safe API for the web app) ----------

-- Idempotent: the same (seller, client_id) returns the existing sale.
DROP PROCEDURE IF EXISTS sp_create_sale//
CREATE PROCEDURE sp_create_sale(
    IN p_seller_id INT, IN p_buyer_account_id INT, IN p_sync_status VARCHAR(10), IN p_client_id CHAR(36))
BEGIN
    DECLARE v_id INT DEFAULT NULL;
    IF p_client_id IS NOT NULL THEN
        SET v_id = (SELECT sale_id FROM Sales WHERE seller_id = p_seller_id AND client_id = p_client_id LIMIT 1);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO Sales (seller_id, buyer_account_id, sync_status, client_id)
        VALUES (p_seller_id, p_buyer_account_id, IF(p_sync_status = 'Offline', 'Offline', 'Online'), p_client_id);
        SET v_id = LAST_INSERT_ID();
    END IF;
    SELECT v_id AS sale_id;
END//

DROP PROCEDURE IF EXISTS sp_add_sale_item//
CREATE PROCEDURE sp_add_sale_item(
    IN p_seller_id INT, IN p_sale_id INT, IN p_product_id INT, IN p_qty DECIMAL(10,3))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sales WHERE sale_id = p_sale_id AND seller_id = p_seller_id AND status = 'Pending') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pending sale not found for this seller.';
    END IF;
    INSERT INTO Sale_Details (sale_id, product_id, quantity_sold, unit_price_at_sale)
    VALUES (p_sale_id, p_product_id, p_qty, 0.00);   -- real price is set by trigger
END//

DROP PROCEDURE IF EXISTS sp_finalize_sale//
CREATE PROCEDURE sp_finalize_sale(IN p_seller_id INT, IN p_sale_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sales WHERE sale_id = p_sale_id AND seller_id = p_seller_id AND status = 'Pending') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pending sale not found for this seller.';
    END IF;
    UPDATE Sales SET status = 'Paid' WHERE sale_id = p_sale_id;
    SELECT receipt_id, receipt_number, receipt_data FROM Receipts WHERE sale_id = p_sale_id;
END//

-- p_seller_id NULL = all sellers (admin job).
DROP PROCEDURE IF EXISTS sp_sync_offline_sales//
CREATE PROCEDURE sp_sync_offline_sales(IN p_seller_id INT)
BEGIN
    UPDATE Sales SET sync_status = 'Online'
    WHERE sync_status = 'Offline' AND (p_seller_id IS NULL OR seller_id = p_seller_id);

    UPDATE Receipts r JOIN Sales s ON s.sale_id = r.sale_id
    SET r.sync_status = 'Synced'
    WHERE r.sync_status = 'Pending' AND (p_seller_id IS NULL OR s.seller_id = p_seller_id);
END//

-- ---------- Accounts: registration, login, tokens ----------

-- A Seller account gets its Sellers profile and capital record automatically.
DROP TRIGGER IF EXISTS trg_accounts_ai//
CREATE TRIGGER trg_accounts_ai AFTER INSERT ON Accounts FOR EACH ROW
BEGIN
    IF NEW.role = 'Seller' THEN
        INSERT INTO Sellers (account_id, first_name, last_name, contact_number, barangay_zone)
        VALUES (
            NEW.account_id,
            LEFT(SUBSTRING_INDEX(TRIM(NEW.username), ' ', 1), 50),
            LEFT(IF(LOCATE(' ', TRIM(NEW.username)) > 0,
                    TRIM(SUBSTRING(TRIM(NEW.username), LOCATE(' ', TRIM(NEW.username)) + 1)), '-'), 50),
            NEW.contact_number,
            LEFT(COALESCE(NULLIF(TRIM(NEW.address), ''), 'Unspecified'), 50)
        );
    END IF;
END//

-- Only Buyer and Seller accounts can be registered here; SLP Admin accounts are inserted by an admin.
DROP PROCEDURE IF EXISTS sp_register_account//
CREATE PROCEDURE sp_register_account(
    IN p_username VARCHAR(50), IN p_email VARCHAR(100), IN p_contact VARCHAR(15),
    IN p_address VARCHAR(150), IN p_password_hash VARCHAR(255), IN p_role VARCHAR(10))
BEGIN
    IF p_role NOT IN ('Buyer', 'Seller') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role must be Buyer or Seller.';
    END IF;
    INSERT INTO Accounts (role, username, email, contact_number, address, password_hash)
    VALUES (p_role, TRIM(p_username), NULLIF(TRIM(p_email), ''), p_contact, p_address, p_password_hash);
    SELECT LAST_INSERT_ID() AS account_id;
END//

-- Look up an account by username, email or contact number; the caller verifies password_hash and checks the lock.
DROP PROCEDURE IF EXISTS sp_get_login//
CREATE PROCEDURE sp_get_login(IN p_identifier VARCHAR(100))
BEGIN
    SELECT account_id, role, username, password_hash,
           (locked_until IS NOT NULL AND locked_until > NOW()) AS is_locked
    FROM Accounts
    WHERE is_active = 1
      AND (username = p_identifier OR email = p_identifier OR contact_number = p_identifier)
    LIMIT 1;
END//

DROP PROCEDURE IF EXISTS sp_login_failed//
CREATE PROCEDURE sp_login_failed(IN p_account_id INT)
BEGIN
    -- locked_until is assigned first so it sees the attempt count BEFORE this increment
    UPDATE Accounts
    SET locked_until = IF(failed_login_attempts + 1 >= 5, DATE_ADD(NOW(), INTERVAL 15 MINUTE), locked_until),
        failed_login_attempts = LEAST(failed_login_attempts + 1, 100)
    WHERE account_id = p_account_id;
END//

DROP PROCEDURE IF EXISTS sp_login_ok//
CREATE PROCEDURE sp_login_ok(IN p_account_id INT)
BEGIN
    UPDATE Accounts
    SET failed_login_attempts = 0, locked_until = NULL, last_login_at = NOW()
    WHERE account_id = p_account_id;
END//

-- Stores only the SHA-256 hash of the token, never the token. Maximum lifetime is 30 days.
DROP PROCEDURE IF EXISTS sp_set_token//
CREATE PROCEDURE sp_set_token(IN p_account_id INT, IN p_token_hash CHAR(64), IN p_hours INT)
BEGIN
    UPDATE Accounts
    SET api_token_hash = p_token_hash,
        api_token_expires_at = DATE_ADD(NOW(), INTERVAL LEAST(GREATEST(p_hours, 1), 720) HOUR)
    WHERE account_id = p_account_id AND is_active = 1;
END//

-- Returns no row when the token is unknown or expired.
DROP PROCEDURE IF EXISTS sp_check_token//
CREATE PROCEDURE sp_check_token(IN p_token_hash CHAR(64))
BEGIN
    SELECT a.account_id, a.role, s.seller_id
    FROM Accounts a
    LEFT JOIN Sellers s ON s.account_id = a.account_id AND s.is_active = 1
    WHERE a.api_token_hash = p_token_hash
      AND a.is_active = 1
      AND a.api_token_expires_at > NOW()
    LIMIT 1;
END//

-- ---------- Inventory: sellers record, SLP Admin verifies ----------

DROP PROCEDURE IF EXISTS sp_record_inventory//
CREATE PROCEDURE sp_record_inventory(
    IN p_seller_id INT, IN p_product_id INT, IN p_type VARCHAR(20),
    IN p_qty DECIMAL(10,3), IN p_remarks VARCHAR(150))
BEGIN
    IF p_type NOT IN ('Harvest/Restock', 'Spoilage') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sellers can only record Harvest/Restock or Spoilage.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Products WHERE product_id = p_product_id AND seller_id = p_seller_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product not found for this seller.';
    END IF;
    INSERT INTO Inventory_Transactions (product_id, transaction_type, verification_status, quantity, remarks)
    VALUES (p_product_id, p_type, 'Pending Review', p_qty, p_remarks);
    SELECT LAST_INSERT_ID() AS transaction_id;
END//

DROP PROCEDURE IF EXISTS sp_verify_inventory//
CREATE PROCEDURE sp_verify_inventory(IN p_txn_id INT, IN p_admin_account_id INT, IN p_status VARCHAR(10))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Accounts WHERE account_id = p_admin_account_id AND role = 'SLP Admin' AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an active SLP Admin can verify inventory.';
    END IF;
    IF p_status NOT IN ('Verified', 'Rejected') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status must be Verified or Rejected.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Inventory_Transactions WHERE transaction_id = p_txn_id AND verification_status = 'Pending Review') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No pending entry with that id.';
    END IF;
    UPDATE Inventory_Transactions
    SET verification_status = p_status, verified_by_account_id = p_admin_account_id
    WHERE transaction_id = p_txn_id;
END//

-- ---------- Contact messages: sender submits, SLP Admin reviews ----------

-- Stores one message. Limits: 5 per hour per number and 10 per hour per visitor.
DROP PROCEDURE IF EXISTS sp_submit_contact_message//
CREATE PROCEDURE sp_submit_contact_message(
    IN p_name VARCHAR(100), IN p_email VARCHAR(100), IN p_contact VARCHAR(15), IN p_subject VARCHAR(50),
    IN p_body TEXT, IN p_token CHAR(32), IN p_ip_hash CHAR(64))
BEGIN
    IF (SELECT COUNT(*) FROM Contact_Messages
        WHERE contact_number = p_contact AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)) >= 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Too many messages from this number. Please try again in an hour.';
    END IF;
    IF p_ip_hash IS NOT NULL AND (SELECT COUNT(*) FROM Contact_Messages
        WHERE ip_hash = p_ip_hash AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)) >= 10 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Too many messages sent. Please try again in an hour.';
    END IF;
    INSERT INTO Contact_Messages (sender_name, sender_email, contact_number, subject, message_body, public_token, ip_hash)
    VALUES (TRIM(p_name), NULLIF(TRIM(p_email), ''), p_contact, p_subject, p_body, p_token, p_ip_hash);
    SELECT LAST_INSERT_ID() AS message_id;
END//

-- The sender reads the status with the message id and its secret token.
DROP PROCEDURE IF EXISTS sp_get_contact_status//
CREATE PROCEDURE sp_get_contact_status(IN p_message_id INT, IN p_token CHAR(32))
BEGIN
    SELECT status FROM Contact_Messages WHERE message_id = p_message_id AND public_token = p_token LIMIT 1;
END//

-- The sender can delete a message: the text is erased and a blank stub stays so the hourly limits still count.
DROP PROCEDURE IF EXISTS sp_delete_contact_message//
CREATE PROCEDURE sp_delete_contact_message(IN p_message_id INT, IN p_token CHAR(32))
BEGIN
    UPDATE Contact_Messages
       SET sender_name = '[deleted]', sender_email = NULL, message_body = '[Deleted by sender]'
     WHERE message_id = p_message_id AND public_token = p_token AND status = 'Review';
    SELECT ROW_COUNT() AS deleted;
END//

DROP PROCEDURE IF EXISTS sp_mark_contact_notified//
CREATE PROCEDURE sp_mark_contact_notified(IN p_message_id INT, IN p_sms TINYINT, IN p_email TINYINT)
BEGIN
    UPDATE Contact_Messages SET sms_sent = p_sms, email_sent = p_email WHERE message_id = p_message_id;
END//

-- SLP Admin decision:  CALL sp_review_contact_message(<message_id>, <admin_account_id>, 'Received' | 'Rejected');
DROP PROCEDURE IF EXISTS sp_review_contact_message//
CREATE PROCEDURE sp_review_contact_message(IN p_message_id INT, IN p_admin_account_id INT, IN p_status VARCHAR(10))
BEGIN
    IF p_status NOT IN ('Received', 'Rejected') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status must be Received or Rejected.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Accounts WHERE account_id = p_admin_account_id AND role = 'SLP Admin' AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an active SLP Admin can review messages.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Contact_Messages WHERE message_id = p_message_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No message with that id.';
    END IF;
    UPDATE Contact_Messages
    SET status = p_status, reviewed_by_account_id = p_admin_account_id, reviewed_at = NOW()
    WHERE message_id = p_message_id;
END//

DELIMITER ;

-- =====================================================================================
-- SECTION 3: REFERENCE DATA (safe to re-run)
-- =====================================================================================

INSERT IGNORE INTO Categories (category_name) VALUES
('Agricultural Products'), ('Raw Materials'), ('Handicrafts'), ('Root Crops'), ('Grains');

-- =====================================================================================
-- SECTION 4: REPORTING VIEWS (read-only; filter by seller_id with a prepared statement)
-- =====================================================================================

DROP VIEW IF EXISTS vw_seller_cash_flow;
CREATE VIEW vw_seller_cash_flow AS
SELECT s.seller_id,
       CONCAT(s.first_name, ' ', s.last_name) AS seller_name,
       s.barangay_zone, s.slp_association,
       COALESCE(ss.total_sales, 0.00) AS total_sales_revenue,
       COALESCE(es.total_expense, 0.00) AS total_expenses,
       COALESCE(ss.total_sales, 0.00) - COALESCE(es.total_expense, 0.00) AS net_cash_flow
FROM Sellers s
LEFT JOIN (SELECT sa.seller_id, SUM(sd.line_total) AS total_sales
           FROM Sales sa JOIN Sale_Details sd ON sd.sale_id = sa.sale_id
           WHERE sa.status = 'Paid' GROUP BY sa.seller_id) ss ON ss.seller_id = s.seller_id
LEFT JOIN (SELECT seller_id, SUM(amount) AS total_expense
           FROM Expenses GROUP BY seller_id) es ON es.seller_id = s.seller_id;

DROP VIEW IF EXISTS vw_inventory_audit;
CREATE VIEW vw_inventory_audit AS
SELECT t.transaction_id, p.seller_id, p.product_name, t.transaction_type, t.quantity,
       t.verification_status, t.remarks, t.transaction_date, t.verified_at
FROM Inventory_Transactions t JOIN Products p ON p.product_id = t.product_id;

DROP VIEW IF EXISTS vw_offline_queue;
CREATE VIEW vw_offline_queue AS
SELECT s.sale_id, s.seller_id, s.sync_status AS sale_sync, r.receipt_number, r.sync_status AS receipt_sync
FROM Sales s LEFT JOIN Receipts r ON r.sale_id = s.sale_id
WHERE s.sync_status = 'Offline' OR r.sync_status = 'Pending';

DROP VIEW IF EXISTS vw_category_sales;
CREATE VIEW vw_category_sales AS
SELECT c.category_id, c.category_name,
       COUNT(DISTINCT p.product_id) AS total_products,
       COALESCE(SUM(x.quantity_sold), 0) AS units_sold,
       COALESCE(SUM(x.line_total), 0.00) AS total_revenue
FROM Categories c
LEFT JOIN Products p ON p.category_id = c.category_id
LEFT JOIN (SELECT sd.product_id, sd.quantity_sold, sd.line_total
           FROM Sale_Details sd JOIN Sales s ON s.sale_id = sd.sale_id
           WHERE s.status = 'Paid') x ON x.product_id = p.product_id
GROUP BY c.category_id, c.category_name;

DROP VIEW IF EXISTS vw_low_stock;
CREATE VIEW vw_low_stock AS
SELECT p.product_id, p.seller_id, p.product_name,
       CONCAT(s.first_name, ' ', s.last_name) AS seller_name,
       p.current_stock, p.reorder_level, p.unit_of_measure
FROM Products p JOIN Sellers s ON s.seller_id = p.seller_id
WHERE p.is_active = 1 AND p.current_stock < p.reorder_level;

DROP VIEW IF EXISTS vw_seller_leaderboard;
CREATE VIEW vw_seller_leaderboard AS
SELECT s.seller_id, CONCAT(s.first_name, ' ', s.last_name) AS seller_name, s.slp_association,
       COUNT(DISTINCT sa.sale_id) AS completed_sales,
       COALESCE(SUM(sd.line_total), 0.00) AS gross_earnings
FROM Sellers s
JOIN Sales sa ON sa.seller_id = s.seller_id AND sa.status = 'Paid'
JOIN Sale_Details sd ON sd.sale_id = sa.sale_id
GROUP BY s.seller_id, s.first_name, s.last_name, s.slp_association;

DROP VIEW IF EXISTS vw_seller_pnl;
CREATE VIEW vw_seller_pnl AS
SELECT s.seller_id, CONCAT(s.first_name, ' ', s.last_name) AS seller_name,
       cm.initial_capital, cm.current_balance,
       COALESCE(e.total_expense, 0.00) AS total_expenses
FROM Sellers s
JOIN Capital_Management cm ON cm.seller_id = s.seller_id
LEFT JOIN (SELECT seller_id, SUM(amount) AS total_expense FROM Expenses GROUP BY seller_id) e
       ON e.seller_id = s.seller_id;

DROP VIEW IF EXISTS vw_receipt_print;
CREATE VIEW vw_receipt_print AS
SELECT receipt_id, sale_id, account_id, receipt_number, issued_at, sync_status,
       JSON_UNQUOTE(JSON_EXTRACT(receipt_data, '$.system')) AS system_header,
       JSON_UNQUOTE(JSON_EXTRACT(receipt_data, '$.payment_status')) AS payment_status,
       receipt_data
FROM Receipts;

-- Never exposes password_hash or api_token_hash.
DROP VIEW IF EXISTS vw_active_staff;
CREATE VIEW vw_active_staff AS
SELECT account_id, username, email, role, is_active, created_at
FROM Accounts
WHERE is_active = 1 AND role IN ('SLP Admin', 'Seller');

-- =====================================================================================
-- SECTION 5: OPERATIONAL AND ANALYTICAL QUERIES
-- Replace the fixed seller_id = 1 with a ? placeholder in a prepared statement.
-- =====================================================================================

SELECT seller_id, seller_name, barangay_zone, slp_association, total_sales_revenue, total_expenses, net_cash_flow 
FROM vw_seller_cash_flow 
ORDER BY net_cash_flow DESC;

SELECT t.transaction_id, p.product_name, t.transaction_type, t.quantity, t.verification_status, t.remarks, t.transaction_date
FROM Inventory_Transactions t
JOIN Products p ON t.product_id = p.product_id
ORDER BY t.transaction_date DESC;

SELECT s.sale_id, s.seller_id, s.sync_status AS sale_sync, r.receipt_number, r.sync_status AS receipt_sync
FROM Sales s
LEFT JOIN Receipts r ON s.sale_id = r.sale_id
WHERE s.sync_status = 'Offline' OR r.sync_status = 'Pending';

EXPLAIN SELECT sa.sale_id, sa.seller_id, SUM(sd.line_total) AS total_amount
FROM Sales sa
JOIN Sale_Details sd ON sa.sale_id = sd.sale_id
WHERE sa.status = 'Paid' AND sa.seller_id = 1
GROUP BY sa.sale_id, sa.seller_id;

SELECT c.category_name, COUNT(DISTINCT p.product_id) AS total_products, COALESCE(SUM(sd.quantity_sold), 0) AS units_sold, COALESCE(SUM(sd.line_total), 0.00) AS total_revenue
FROM Categories c
LEFT JOIN Products p ON c.category_id = p.category_id
LEFT JOIN (SELECT d.product_id, d.quantity_sold, d.line_total
           FROM Sale_Details d JOIN Sales sa ON sa.sale_id = d.sale_id
           WHERE sa.status = 'Paid') sd ON p.product_id = sd.product_id
GROUP BY c.category_id, c.category_name
ORDER BY total_revenue DESC;

SELECT p.product_id, p.product_name, CONCAT(s.first_name, ' ', s.last_name) AS seller_name, p.current_stock, p.unit_of_measure
FROM Products p
JOIN Sellers s ON p.seller_id = s.seller_id
WHERE p.current_stock < p.reorder_level AND p.is_active = 1
ORDER BY p.current_stock ASC;

SELECT s.seller_id, CONCAT(s.first_name, ' ', s.last_name) AS seller_name, s.slp_association, COUNT(DISTINCT sa.sale_id) AS completed_sales, COALESCE(SUM(sd.line_total), 0.00) AS gross_earnings
FROM Sellers s
JOIN Sales sa ON s.seller_id = sa.seller_id
JOIN Sale_Details sd ON sa.sale_id = sd.sale_id
WHERE sa.status = 'Paid'
GROUP BY s.seller_id, s.first_name, s.last_name, s.slp_association
ORDER BY gross_earnings DESC;

SELECT s.seller_id, CONCAT(s.first_name, ' ', s.last_name) AS seller_name, cm.initial_capital, cm.current_balance, COALESCE(e.total_expense, 0.00) AS total_expenses
FROM Sellers s
JOIN Capital_Management cm ON s.seller_id = cm.seller_id
LEFT JOIN (
    SELECT seller_id, SUM(amount) AS total_expense FROM Expenses GROUP BY seller_id
) e ON s.seller_id = e.seller_id
WHERE s.seller_id = 1;

SELECT receipt_id, receipt_number, JSON_UNQUOTE(JSON_EXTRACT(receipt_data, '$.system')) AS system_header, JSON_UNQUOTE(JSON_EXTRACT(receipt_data, '$.payment_status')) AS status
FROM Receipts
WHERE sync_status = 'Synced';

SELECT account_id, username, email, role, is_active, created_at
FROM Accounts
WHERE is_active = 1 AND role IN ('SLP Admin', 'Seller')
ORDER BY created_at DESC;

SELECT t.transaction_id, p.product_name, CONCAT(s.first_name, ' ', s.last_name) AS seller_name, t.transaction_type, t.quantity, p.unit_of_measure, t.transaction_date, t.remarks
FROM Inventory_Transactions t
JOIN Products p ON t.product_id = p.product_id
JOIN Sellers s ON p.seller_id = s.seller_id
WHERE t.verification_status = 'Pending Review'
ORDER BY t.transaction_date ASC;

SELECT ledger_id, entry_type, amount, balance_after, reference_id, note, created_at
FROM Capital_Ledger
WHERE seller_id = 1
ORDER BY ledger_id DESC;

SELECT cm.seller_id, cm.current_balance, cm.initial_capital + COALESCE(l.total, 0.00) AS expected_balance
FROM Capital_Management cm
LEFT JOIN (SELECT seller_id, SUM(amount) AS total FROM Capital_Ledger GROUP BY seller_id) l ON l.seller_id = cm.seller_id
WHERE cm.current_balance <> cm.initial_capital + COALESCE(l.total, 0.00);

SELECT p.product_id, p.product_name, p.current_stock, COALESCE(t.net, 0.000) AS expected_stock
FROM Products p
LEFT JOIN (SELECT product_id,
                  SUM(CASE WHEN transaction_type IN ('Harvest/Restock', 'Adjustment') THEN quantity ELSE -quantity END) AS net
           FROM Inventory_Transactions
           WHERE verification_status = 'Verified'
           GROUP BY product_id) t ON t.product_id = p.product_id
WHERE p.current_stock <> COALESCE(t.net, 0.000);

-- =====================================================================================
-- SECTION 6: LEAST-PRIVILEGE USERS (optional, recommended; edit names and passwords first)
-- Triggers and procedures run with definer rights, so the app user needs no direct write access
-- to stock, capital, ledger, accounts or inventory.
-- =====================================================================================
-- CREATE USER 'uswag_app'@'localhost' IDENTIFIED BY 'CHANGE_ME_LONG_RANDOM';
-- GRANT SELECT ON uswag_db.Sellers TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Categories TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Products TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Sales TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Sale_Details TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Inventory_Transactions TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Expenses TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Capital_Management TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Capital_Ledger TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.Receipts TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.vw_seller_cash_flow TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.vw_low_stock TO 'uswag_app'@'localhost';
-- GRANT SELECT ON uswag_db.vw_receipt_print TO 'uswag_app'@'localhost';
-- No SELECT on Accounts: login goes through sp_get_login, so password hashes are never browsable.
-- GRANT INSERT, UPDATE (product_name, unit_of_measure, unit_price, reorder_level, is_active, category_id)
--       ON uswag_db.Products TO 'uswag_app'@'localhost';
-- GRANT INSERT, UPDATE, DELETE ON uswag_db.Expenses TO 'uswag_app'@'localhost';
-- GRANT UPDATE (is_downloaded) ON uswag_db.Receipts TO 'uswag_app'@'localhost';
-- GRANT UPDATE (first_name, last_name, contact_number, barangay_zone, slp_association) ON uswag_db.Sellers TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_register_account TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_get_login TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_login_ok TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_login_failed TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_set_token TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_check_token TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_record_inventory TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_create_sale TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_add_sale_item TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_finalize_sale TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_sync_offline_sales TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_submit_contact_message TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_get_contact_status TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_mark_contact_notified TO 'uswag_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_delete_contact_message TO 'uswag_app'@'localhost';
-- Do not grant EXECUTE on sp_capital_move: it is internal.
--
-- A second user for admins, so sellers can never call sp_verify_inventory.
-- CREATE USER 'uswag_admin'@'localhost' IDENTIFIED BY 'CHANGE_ME_ANOTHER_LONG_RANDOM';
-- GRANT SELECT ON uswag_db.* TO 'uswag_admin'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_verify_inventory TO 'uswag_admin'@'localhost';
-- GRANT EXECUTE ON PROCEDURE uswag_db.sp_review_contact_message TO 'uswag_admin'@'localhost';
--
-- The app user can register, log in, issue tokens and sync sales, but it cannot read Accounts or write stock or capital.
--
-- First SLP Admin: never ship a default password. Create the hash on your own computer, then run the INSERT as an admin.
--   php -r "echo password_hash('YOUR-LONG-PASSWORD', PASSWORD_DEFAULT);"
-- INSERT INTO Accounts (role, username, contact_number, address, password_hash)
-- VALUES ('SLP Admin', 'Your Name', '09XXXXXXXXX', 'Aniog, Sagñay, Camarines Sur', '<paste the hash here>');

-- =====================================================================================
-- SECTION 7: SAMPLE DATA (uses the real procedures, so every trigger fires)
-- =====================================================================================
CALL sp_register_account('manay_seller','manay@uswag.ph','09917435671','Zone 1, Aniog, Sagnay','$2b$10$demoHashSeller','Seller');
CALL sp_register_account('manoy_seller','manoy@uswag.ph','09917543793','Zone 2, Aniog, Sagnay','$2b$10$demoHashSeller2','Seller');
CALL sp_register_account('buyer_demo','buyer@uswag.ph','09170000001','Goa, Camarines Sur','$2b$10$demoHashBuyer','Buyer');
INSERT INTO Accounts (role,username,email,contact_number,address,password_hash)
VALUES ('SLP Admin','uswag_admin','admin@uswag.ph','09081234567','Aniog SLPA Office','$2b$10$demoHashAdmin');
SET @admin = (SELECT account_id FROM Accounts WHERE username='uswag_admin');
SET @s1 = (SELECT seller_id FROM Sellers ORDER BY seller_id LIMIT 1);
SET @s2 = (SELECT seller_id FROM Sellers ORDER BY seller_id LIMIT 1 OFFSET 1);
SET @buyer = (SELECT account_id FROM Accounts WHERE username='buyer_demo');
INSERT INTO Products (seller_id,category_id,product_name,unit_of_measure,unit_price)
SELECT @s1,(SELECT category_id FROM Categories WHERE category_name='Agricultural Products'),'Copra','kg',45.00 UNION ALL
SELECT @s1,(SELECT category_id FROM Categories WHERE category_name='Handicrafts'),'Walis Ting-ting','piece',35.00 UNION ALL
SELECT @s2,(SELECT category_id FROM Categories WHERE category_name='Root Crops'),'Cassava','kg',25.00;
CALL sp_record_inventory(@s1,1,'Harvest/Restock',500,'Copra harvest');
CALL sp_record_inventory(@s1,2,'Harvest/Restock',100,'Walis batch');
CALL sp_record_inventory(@s2,3,'Harvest/Restock',250,'Cassava harvest');
UPDATE Capital_Management SET initial_capital = 5000 WHERE seller_id=@s1;
UPDATE Capital_Management SET initial_capital = 3000 WHERE seller_id=@s2;
CALL sp_verify_inventory(1,@admin,'Verified');
CALL sp_verify_inventory(2,@admin,'Verified');
CALL sp_verify_inventory(3,@admin,'Verified');
CALL sp_create_sale(@s1,@buyer,'Online',UUID());
CALL sp_add_sale_item(@s1,1,1,50);
CALL sp_add_sale_item(@s1,1,2,10);
CALL sp_finalize_sale(@s1,1);
CALL sp_create_sale(@s2,NULL,'Offline',UUID());
CALL sp_add_sale_item(@s2,2,3,20);
INSERT INTO Expenses (seller_id,expense_category,amount,description) VALUES (@s1,'Raw Materials/Seeds',1500.00,'Coconut palm fertilizer');