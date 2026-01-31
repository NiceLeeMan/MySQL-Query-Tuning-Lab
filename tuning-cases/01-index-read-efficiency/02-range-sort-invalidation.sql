/*
 [CASE 02] hire_date 인덱스를 활용한 범위 검색, 정렬 및 가공 실험
 - 대상 요구사항: 2번(Range Scan), 5번(Order By), 10번(Index Invalidation)
*/

CREATE INDEX idx_hiredate ON employees_bulk(hire_date);

-- 1. [Requirement 2] 범위 검색 실험 (BETWEEN)
/*
1. 예상동작 및 결과
    - hire_date B-Tree 에서 출발해 범위값을 따지며 리프노드까지 이동 할 것같음.
    - 리프노드에 에서 페이지의 레코드 단위로 읽음.
    - 레코드 읽기 -> 레코드의 Value 값인 PK를 통해 데이터 파일 접근 -> 다음 레코드로 이동 : 이 과정을 hire_date = 1995-12-31 까지 반복
    - 예상 실행계획 : type.rage , key.idx_hiredate, rows.183800 extra.Using index condition
2. 실제결과 :
    - 예상동작과 일치
3. 의문과 해답
*/
EXPLAIN SELECT * FROM employees_bulk WHERE hire_date BETWEEN '1995-01-01' AND '1995-12-31';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE hire_date BETWEEN '1995-01-01' AND '1995-12-31';
SHOW STATUS LIKE 'Handler_read%';

/*
1. 예상동작 및 결과
    -위의 SQL과 똑같을 것 같음.
2. 실제결과 :
    - 예상 동작과 다름
    - type.All , key.null, rows.2391204, Extra.Using where
3. 의문과 해답
    - 분명 인덱스를 걸었고 위의 SQL문과 WHERE절 범위를 제외한 모든게 같은데 왜 다를까?
    - 일반적으로 Range가 전체 데이터의  30%를 오바하면 옵티마이저는 인덱스를 타지 않고 Table_Full_Scan 방식으로 데이터를 읽어온다.
    - 이유은 인덱스 리프 노드에서 찾은 PK를 가지고 실제 데이터 페이지를 찾아가는 '랜덤 I/O'가 발생. 읽어올 레코드가 70만개라면 70만번의 랜덤I/O 발생.
*/
EXPLAIN SELECT * FROM employees_bulk WHERE hire_date BETWEEN '1990-01-01' AND '1995-12-31';
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE hire_date BETWEEN '1990-01-01' AND '1995-12-31';
SHOW STATUS LIKE 'Handler_read%';

/*
1. 예상동작 및 결과
    -위의 SQL과 똑같을 것 같음.
2. 실제결과 :
    - 예상 동작과 다름
    - type.range , key.idx_hiredate, rows.1195602, Extra.Using where; Using index
3. 의문과 해답
    - 분명 위의 SQL과 범위가 같은데 왜 그럴까?
    - 추출하는 데이터가 이미 인덱스 B-Tree에 존재하기 때문, 즉 커버링 인덱스를 타서 굳이 데이터 파일까지 접근하지 않기 때문
    - 만약 커버링 인덱스를 못타는 다른 컬럼(last_name,birth_date 같은 거면 예상 동작대로 작동했을 거임)
*/
EXPLAIN SELECT emp_no, hire_date FROM employees_bulk WHERE hire_date BETWEEN '1990-01-01' AND '1995-12-31';
FLUSH STATUS;
SELECT emp_no, hire_date FROM employees_bulk WHERE hire_date BETWEEN '1990-01-01' AND '1995-12-31';
SHOW STATUS LIKE 'Handler_read%';

/*
1. 예상동작 및 결과
    - Table_full_Scan 을 할것 같음.
    - WHERE 절의 YEAR과 idx_hiredate의 값이 다름. B-Tree에 존재하지 않는 Key 값이라 PK-BTree를 타서 데이터 파일에 접근할듯.
    - type.All, key.null, Extra.Using where
2. 실제결과 :
    - 예상 동작같음
3. 의문과 해답
    - possible_keys 자체가 null. 이는 인덱스 B-Tree의 키 값 과 YEAR(hire_date)자체가 다르기에, 인덱스 트리 자체를 안탐.
    - 이전의 possible_key값은 있지만 key.null인 경우와 다름.
*/
EXPLAIN SELECT * FROM employees_bulk WHERE YEAR(hire_date) = 1995;
FLUSH STATUS;
SELECT * FROM employees_bulk WHERE YEAR(hire_date) = 1995;
SHOW STATUS LIKE 'Handler_read%';

/*
1. 예상동작 및 결과
    - SELECT * 라서 데이터 파일 접근을 피할 수 없어보임. Table_Full_Scan 가능성 있어보임.
    - 하지만 B-Tree 리프노드에 이미 hire_date로 정렬되어있음. 가장 중요한건 10개만 읽어오면됨.
    - 고로 리프노드의 랜덤 I/O가 10번만 발생할것임.
    - Type.Range , 나머지 속성은 예상안감.
2. 실제결과 :
    - type.index, possible_key.null, key.idx_hiredate, Extra.null
3. 의문과 해답
    - type.index: type.range 는 특정 시작점과 끝점이 있는 범위 검색일 때 발생한다.
    반면, 이 쿼리는 인덱스의 첫 번째 레코드부터 순서대로 읽기 시작하므로 Full Index Scan을 의미하는 index 타입이 나타난다.
    -SELECT *의 패널티 상쇄: 보통 범위가 넓으면 SELECT * 때문에 풀 스캔을 선택하지만,
    여기서는 LIMIT이 읽어야 할 양을 극단적으로 줄여주었기 때문에 옵티마이저가 인덱스를 선택한 것
*/
EXPLAIN SELECT * FROM employees_bulk ORDER BY hire_date ASC LIMIT 10;
FLUSH STATUS;
SELECT * FROM employees_bulk ORDER BY hire_date ASC LIMIT 10;
SHOW STATUS LIKE 'Handler_read%';

ALTER TABLE employees_bulk DROP INDEX idx_hiredate;

/**
 이번 실습 과제에서의 의의는 다음과 같아.
 1. B-Tree 인덱스는 항상 '빠른 길'이 아니다. 옵티마이저는 비용 기반(CBO)으로 작동하며,
    읽어야 할 데이터가 전체의 약 20~25%를 넘어서면 인덱스를 포기하고 풀 스캔을 선택한다.
 2. 인덱스 레인지 스캔의 성능 저하 주범은 '인덱스 그 자체'가 아니라,
    리프 노드에서 데이터 파일로 점프하는 수십만 번의 랜덤I/O에 있음을 확인했다.
 3. 하지만 '커버링 인덱스'를 활용하면 데이터 파일에 접근하지 않으므로,범위가 넓어도 풀 테이블 스캔보다 압도적인 성능 보여준다.
 4. 정렬 최적화의 핵심은 B-Tree 리프 노드가 이미 정렬되어 있다는 점을 이용하는 것이다.
    이를 통해 CPU 부하가 큰 연산을 제거하고 응답 속도를 단축할 수 있다.
 5. 인덱스 컬럼을 함수(YEAR() 등)로 가공하면 B-Tree의 정렬 구조를 검색에 활용할 수 없는 상태가 되어 인덱스가 무효화됨을 확인했다.
 6. LIMIT 절은 넓은 범위의 인덱스 스캔에서도 읽어야 할 랜덤I/O 횟수를 강제로 제한하여
    옵티마이저가 인덱스 경로를 포기하고, 데이터 파일에 접근하지 않도록 해준다.
  결론적으로, 개발자는 단순히 인덱스를 '거는 것'에 그치지 않고, 데이터의 분포와 I/O 비용을 고려하여
  옵티마이저가 최적의 경로를 선택할 수 있도록 쿼리를 설계해야 한다.
 */














