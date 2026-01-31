/*
 [CASE 03] 복합 인덱스와 Leftmost Prefix 규칙
 - 대상 요구사항: 6번 (복합 인덱스 컬럼 순서의 중요성)
 - 핵심 포인트: 다중 컬럼 인덱스에서 선행 컬럼 없이 후행 컬럼만으로 검색 시 발생하는 현상 분석
*/


-- (first_name, last_name) 순서의 복합 인덱스 생성
CREATE INDEX idx_name_composite ON employees_bulk(first_name, last_name);


-- =================================================================
-- [CASE 01] 복합 인덱스의 순서쌍과 일치하게 조회했을 때 (동등 연산)
-- =================================================================
/*
1. 예상동작 및 결과:
    - type.ref, key.idx_name_composite, extra.null
2. 실제결과 :
    - 예상과 일치
3. 의문과 해답 :
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE first_name = 'Georgi' AND last_name = 'Facello';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name = 'Georgi' AND last_name = 'Facello';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 02] 복합 인덱스의 순서쌍과 반대로 조회했을 때 (동등 연산)
-- =================================================================
/*
1. 예상동작 및 결과:
    - type.all key.null, extra.null
2. 실제결과 :
    - type.ref, key.idx_name_composite, extra.using where
3. 의문과 해답 :
    - Q1 인덱스 순서쌍을 바꿔서 조회했는데, 왜 결과가 같지?
    - A1 MySQL 옵티마이저는 사용자가 작성한 SQL을 그대로 실행하지 않고, 내부적으로 최적의 경로를 찾기 위해 조건을 재배열한다.
         AND 조건은 논리적으로 순서가 바뀌어도 결과가 동일하므로,
         옵티마이저가 인덱스 순서인 (first_name, last_name)에 맞춰 검색 순서를 자동으로 조정
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE last_name = 'Facello' AND first_name = 'Georgi';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE last_name = 'Facello' AND first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 03] 선행 컬럼은 범위, 후행 컬럼은 동등 연산으로 조회했을 때
-- =================================================================
/*
1. 예상동작 및 결과:
    - 리프노드에서 first_name > Z인 레코드의 수에 따라 다를 듯.
    - 이는 실행 계획을 먼저 까서 결론을 내리는 것에 의미가 있음. 예측이 의미 없다 생각.
    - 만약 인덱스를 탄다면 type.range, 아니라면 type.All
    - Z가 아니라 A로 바꿔서 한다면 무조건 type.All 일 것임.
2. 실제결과 :
    - type.range, key.idx_name_composite ,Extra.Using index condition
3. 의문과 해답 :
    - Q1 Using index condition 의 의미
    - A1 ICP사용, 데이터 파일에 접근하긴 하나, 꼭 필요한 애들만 필터링 해서감.
*/
EXPLAIN SELECT emp_no FROM employees_bulk
        WHERE first_name > 'Z' AND last_name = 'Facello';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name > 'Z' AND last_name = 'Facello';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 04] 복합 인덱스의 선행 컬럼(first_name)을 누락하고 조회했을 때
-- =================================================================
/*
1. 예상동작 및 결과:
    - 인덱스를 못타서 풀 스캔 할 것 같음.
    - 인덱스 B-Tree 의 레코드 구조 (first_name, last_name, value) 임. first_name 조건이 WHERE 절에 없어서, 전체 레코드 읽어야함.
    - type.all , key.null, extra.using Where
2. 실제결과 :
    - 예상과 같음.
3. 의문과 해답 :
    - Q1 type.All인 구체적인 이유가 뭔가요? 인덱스 트리의 레코드를 모두 읽어서 그런 것인가?
    - A1 그런것은 아니다. 사실 인덱스 B-Tree의 전체 레코드만 읽는것은 비용이 안 크다. 문제는 데이터 파일에 접근하는 과정에서 랜덤I/O가 발생한다는 점 문제
         아래 SQL에서 *가 아니라 인덱스 트리에 있는 컬럼(first_name, last_name, emp_no)라면 type.range가 나온다. 반면에 birth_date를 조회했다면 type.all 발생

    - Q2. 그렇다면 왜 type.range인가요? last_name에는 '='인데 인덱스를 타고 type.ref를 타야하는거 아닌가?
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE last_name = 'Facello';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE last_name = 'Facello';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 05] 복합 인덱스의 선행 컬럼(first_name)만 사용하여 조회했을 때
-- =================================================================
/*
1. 예상동작 및 결과:
    - type.ref, extra.null 나오며 인덱스 잘 탈것임.
2. 실제결과 :
    - 예상과 같음
3. 의문과 해답 :
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE first_name = 'Georgi';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name = 'Georgi';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 06] 선행 컬럼 동등 조건 후, 후행 컬럼으로 정렬(ORDER BY)할 때
-- =================================================================
/*
1. 예상동작 및 결과:
    - 커버링 인덱스 타고 끝남. last_name 은 이미 리프 노드에서 정렬되어 있음
2. 실제결과 :
    - 예상과 일치
3. 의문과 해답 :
    - Q1 ORDER BY의 정렬방향이 DESC 였다면?
    - A1 Inno DB가 그런경우 읽는 방향을 아래 -> 위로 읽음.(교재 8.3.6.1.1 인덱스 스캔방향 참조)
*/
EXPLAIN SELECT emp_no FROM employees_bulk
        WHERE first_name = 'Georgi'
        ORDER BY last_name LIMIT 10;
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name = 'Georgi' ORDER BY last_name LIMIT 10;
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 07] LIKE 연산자 사용 시 - 뒤에 와일드카드가 있는 경우 (Prefix)
-- =================================================================
/*
1. 예상동작 및 결과:
    -인덱스 잘 탈거같음. 그리고 first_name > 'G' 보다 더 검색속도 빠를 것같음.
    - LIKE 의 '%'자체가 사실 범위연산자와 같다고 봄.
    - type.range, Extra.Using index condition(인덱스 2번타야함. 근데  Geo% 때문에 범위가 좁혀짐, 아마 >'G'면 using Where 나올듯.)
2. 실제결과 :
    - 예상과 같음
3. 의문과 해답 :
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE first_name LIKE 'Geo%';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name LIKE 'Geo%';
SHOW STATUS LIKE 'Handler_read%';


-- =================================================================
-- [CASE 08] LIKE 연산자 사용 시 - 앞에 와일드카드가 있는 경우 (Suffix)
-- =================================================================
/*
1. 예상동작 및 결과:
    - 풀스캔. 이번엔 %가 앞에 있는데 이러면 A~Z까지 다 찾아야함. 문제는 앞의 %는 문자열 개수를 포함하는게 아니라 A~Z찾기를 2번이상 반복할수도 있음.
2. 실제결과 :
3. 의문과 해답 :
*/
EXPLAIN SELECT * FROM employees_bulk
        WHERE first_name LIKE '%orgi';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE first_name LIKE '%orgi';
SHOW STATUS LIKE 'Handler_read%';