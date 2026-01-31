CREATE TABLE employees_bulk LIKE employees;

INSERT INTO employees_bulk SELECT * FROM employees;

SELECT count(*) FROM employees_bulk;

-- ---------------------------------------------------------
-- 이 쿼리 전체를 3~4회 반복 실행
-- ---------------------------------------------------------

-- 1. 현재 테이블의 가장 큰 사원 번호를 변수에 저장 (PK 중복 방지용)
SELECT @max_emp_no := MAX(emp_no) FROM employees_bulk;

-- 2. 현재 데이터만큼 복사해서, 사원번호만 증가시켜 다시 넣기 (2배씩 증가)
INSERT INTO employees_bulk (emp_no, birth_date, first_name, last_name, gender, hire_date)
SELECT
    emp_no + @max_emp_no, -- 기존 번호 + 최대값 = 겹치지 않는 새 번호
    birth_date,
    first_name,
    last_name,
    gender,
    hire_date
FROM employees_bulk;

-- 행 개수 몇개인지 파악 (최종적으로 2400192개)
SELECT count(*) FROM employees_bulk;