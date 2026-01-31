/*
 [CASE 01] 단건 조회(Simple Lookup)와 인덱스의 기본 원리
 - 대상 요구사항: 1번(Simple Lookup), 3번(Covering Index), 4번(Double Look-up)
 - 핵심 포인트: WHERE 절 필터링 성능과 SELECT 절 컬럼 구성에 따른 Random I/O 차이 분석
*/

-- =================================================================
-- 실험 1: PK인 emp_no만 조회 (SELECT emp_no ...)
-- =================================================================
/*
 [분석 내용]
 1. 초기 예상:
    - "emp_no는 PK니까 PK 인덱스를 타고 빠르게 조회하지 않을까?"
 2. 실제 결과:
    - type: ALL (Full Table Scan)
    - Handler_read_rnd_next: 약 240만 (전체 행 개수)
 3. 이유 (Why?):
    - SQL 실행 순서는 [FROM -> WHERE -> SELECT] 입니다.
    - DB는 WHERE 절의 'Georgi'를 찾기 위해 테이블을 뒤져야 합니다.
    - 그런데 first_name에 대한 (B-Tree)가 없으므로, 정렬된 PK 인덱스(Clustered Index) 전체를 순차적으로 다 읽어야 합니다.
    - 결국 'Georgi'를 찾기 위해 풀 스캔을 해야 하므로, 결과로 emp_no만 반환하는 것은 성능에 영향을 주지 못합니다.
*/
EXPLAIN SELECT emp_no FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT emp_no FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';

-- =================================================================
-- 실험 2: 모든 컬럼 조회 (SELECT * ...)
-- =================================================================
/*
 [분석 내용]
 1. 예상:
    - "풀 스캔을 할 것이다."
 2. 실제 결과:
    - type: ALL (Full Table Scan)
    - Handler_read_rnd_next: 약 240만 (동일)
 3. 이유:
    - 실험 1과 동일한 이유입니다. first_name을 찾기 위해 전체를 읽는 비용(Disk I/O)이 지배적입니다.
*/
EXPLAIN SELECT * FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- 실험 3: 인덱스 없는 컬럼 조회 (SELECT last_name ...)
-- =================================================================
/*
 [분석 내용]
 1. 예상:
    - "last_name도 인덱스가 없으니 풀 스캔일 것이다."
 2. 실제 결과:
    - type: ALL (Full Table Scan)
    - Handler_read_rnd_next: 약 240만 (동일)
 3. 결론:
    - 셋 다 똑같습니다.
    - WHERE 절에서 인덱스를 타지 못하면
    - SELECT 절에 무엇을 적든 240만 건을 다 읽어야 하는 운명은 바뀌지 않습니다.
*/
EXPLAIN SELECT last_name FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT last_name FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';


CREATE INDEX idx_firstname ON employees_bulk(first_name);


-- =========================================================
-- [CASE B] 세컨더리 인덱스(idx_firstname) 생성 후 조회 실험
-- ========================================================


-- =================================================================
-- 실험 1: 커버링 인덱스 (SELECT emp_no, first_name ...)
-- =================================================================
/*
1. 예상 결과:
    -first_name 에 인덱스가 걸려있으므로 인덱스를 탈 것이다., 조회하는 컬럼은 emp_no, first_name 이며,
    이 둘은 first_name B-Tree 의 리프노드에 존재 하므로 데이터 파일까지 가지 않을 것이다.
2. 실제 결과:
    - type: ref
    - key: idx_firstname
    - Extra: Using index (인덱스 B-Tree에서 해결)

3. 이유:
    - 커버링 인덱스 때문임.
    - InnoDB의 세컨더리 인덱스는 구조적으로 [Key: first_name / Value: PK(emp_no)]를 가진다.
    - 필요한 모든 데이터가 인덱스 페이지 안에 다 있어서, 실제 테이블(데이터 파일)을 열어볼 필요가 없음. (가장 빠름)
*/
EXPLAIN SELECT emp_no,first_name FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT emp_no,first_name FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';

-- =================================================================
-- 실험 2: 인덱스 없는 컬럼 포함 (SELECT emp_no, last_name ...)
-- =================================================================
/*
1. 예상 결과:
    -first_name 에 인덱스가 걸려있으므로 인덱스를 탈 것이다. 하지만 B-Tree 리프노드에는 last_name에 대한 값이 없으므로
    리프노드에서 PK를 통해 데이터 파일에 접근해서 그 안에서 PK를 기준으로 인덱스를 한번 더 탈것이다. extra.null 예상
2. 실제 결과:
    - type: ref
    - key: idx_firstname
    - Extra: NULL (Using index 없음)
3. 이유:
    - 'Georgi'를 찾는 건 인덱스로 해결했음(Ref).
    - 하지만 last_nam e은 인덱스에 없음.
    - 따라서 인덱스에서 찾은 PK(emp_no)를 들고, 다시 클러스터드 인덱스(데이터 파일)를 뒤져서 last_name을 가져오는 '랜덤 I/O'가 발생했음.
*/
EXPLAIN SELECT emp_no,last_name FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT emp_no,last_name FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';

-- =================================================================
-- 실험 3: 모든 컬럼 조회 (SELECT * ...)
-- =================================================================
/*
 [분석 내용]
 1. 예상 결과:
    - "실험 2와 마찬가지로 테이블을 방문해야 할 것이다." 하지만 실제 서비스에서 성능은 더 떨어질것. WAS 와 네트워크 때문에
 2. 실제 결과:
    - type: ref
    - key: idx_firstname
    - Extra: NULL
 3. 이유:
    - 실험 2와 메커니즘이 완벽하게 동일.
    - 인덱스에 없는 컬럼(birth_date, gender 등)을 가져오기 위해,
    - 검색된 2,024건에 대해 모두 데이터 파일 접근(Random Lookup)이 발생
    - 즉, 인덱스를 탔지만 '커버링 인덱스'는 실패
*/
EXPLAIN SELECT * FROM employees_bulk WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';


DROP INDEX idx_firstname ON employees_bulk;

/**
  이번 실습 과제에서의 의의는 다음과 같아.
  1. 인덱스가 없을 때, 데이터베이스 베이스는 기본적으로 데이터 파일에 접근해서 Table_full_scan 을 한다.
  2. 인덱스를 걸어두면 해당 세컨더리 인덱스(ex first_name)과 PK를 통해 B-Tree 를 만든다.
  3. 이때 데이터 조회 시 인덱스 B-Tree 만 타는 커버링 인덱스와 데이터 파일까지 다 읽는 방식 2가지가 존재한다.
  4. 전자의 경우는 조회 시 인덱스 컬럼 & PK 값을 조회하는 경우,
  5. 후자의 경우는 인덱스 B-Tree 에 없는 기타 컬럼(ex last_name, hire_date, 등등 )을 조회할때 발생.
  6. 이는 SELECT * 사용을 지양하는 이유와 직결된다. 커버렁 인덱스를 활용할 수 없기 때문임.
  7. 실행계획이 의미하는 바가 무엇인지 자연어로 표현하는 연습도 해봄.

  결론적으로 인덱스 설정을 피할 수 없다. 그리고 대부분의 조회문에서는 커버링 인덱스만으로 조회가 끝나기는 쉽지 않다. (요구사항 때문)
  하지만 DB의 성능이 중요하다면 이런 부분들을 활용할 수 있게 쿼리를 튜닝하는 연습도 중요하다. 아마 WAS-DB 사이의 조율을 잘 해야할 듯.
  */