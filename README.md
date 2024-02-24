# ElasticBeanstalk Single Instance + Docker + Certbot LetsEncrypt SSL

Essa é uma documentação que explica os conceitos da geração de certificados SSL através do certbot para aplicações ElasticBeanstalk que possuem apenas uma instância (para aplicações com pouco acesso), e que portanto, não utilizam do mecânismo de LoadBalancer (que pode ser custo consideravel para uma aplicação pequena) e por consequência não conseguem aplicar os certificados ACM gerenciados pela AWS.

Esse documento tem como objetivo detalhar todos os passos utilizados para o levantar a insfraestrutura da aplicação, bem como explicar os conceitos por trás do certbot que levaram a implementação do script `/nginx/entrypoint.sh`

## Tecnologias e Ferramentas Utilizadas

- AWS como infraestrutura de Cloud;
- GitLab como repositório de código;
- GitLab como ferramenta de CI;
- Serverless Framework como IaC;
- Nginx como reverse proxy;
- PHP como aplicação de exemplo;
- Certbot para gerenciamento to certificado SSL;

_Esse documento tem como objetivo detalhar também as nuâncias do ElasticBeanstalk, mas pode ser fácilmente adaptado para trabalhar com instâncias EC2 sem a necessidade do mesmo._

## Insfraestrutura como Código - IaC

Esse projeto tem o objetivo de tornar o deploy de uma nova aplicação o mais simples possível, portanto foram utilizadas uma série de variáveis de ambiente para que as nomenclaturas da sua infraestrutura possam obedecer a essas variáveis ao invés de serem alteradas manualmente nos arquivos de CI.

### 1 - Tarefas manuais - Antes de executar o CI

#### 1.1 - Contas e Apontamento DNS
_Para que todos os recursos possam se comunicar de forma adequada, é necessário que você possua as contas informadas abaixo, bem como realize as configurações de apontamento DNS do seu domínio e credenciais de acesso programático na AWS._

1. Ter uma conta na **AWS** disponível;
2. Ter uma conta no **GitLab** disponívei;
3. Criar uma Zona Hospedada no **Rout53** da AWS para o seu domínio;
4. Possuir um **domínio** registrado apontando para o DNS da sua Zona Hospedada no Route53 da AWS;
5. Criar um **Usuário IAM** na AWS com permissão Administrativa para o gerenciamento do seus recursos de cloud por IaC e sua respectiva **Chave de Acesso**;

#### 1.2 - Definição das variáveis de ambiente no GitLab

_Uma vez com os passos anteriores devidamente configurados, agora é possível definir as variáveis de ambiente que iremos utilizar em todo o nosso processo de CI, abaixo estão listadas cada uma delas, bem como o objetivo de sua utilização. Essas variáveis deverão ser adicionadas ao seu projeto do GitLab em `Settings > CI/CD > Variables`._

_No gerenciamento de variáveis do GitLab, será possível atribuir valores de variáveis diferentes para cada ambiente da sua aplicação, permitindo que você defina subdominios diferentes para seus ambientes ou até mesmo regiões AWS diferentes. **ATENÇÃO:** Não tente realizar o deploy dos seus ambientes em contas AWS diferentes a menos que você possua dominios diferentes, pois os domínios só podem ser gerenciados por apenas um NameServer de cada vez._

1. **AWS_ACCESS_KEY_ID**: Nome da chave de acesso gerada no momento da criação do seu usuário IAM, responsável por autenticar com a sua conta AWS no momento do CI e permitir que os recursos definidos na IaC sejam criados;

2. **AWS_SECRET_ACCESS_KEY**: Segredo da chave de acesso gerada no momento da criação do usuário IAM, responsável por autenticar com a sua conta AWS no momento do CI e permitir que os recursos definidos na IaC sejam criados;

3. **AWS_DEFAULT_REGION**: Região da AWS em que você deseja realizar o deploy da sua aplicação;

4. **HOSTED_ZONE_ID**: ID gerada ao criar uma Zona Hospedada no Route53 para o seu domónio. Essa informação é necessária para criar um **RecordSet** que aponta o seu domínio para o deploy da sua aplicação no Elastic Beanstalk (_O apontamento relizado no momento do CI é extremamente importante para que o dominio responda o mais rápido possível para a sua aplicação, permitindo que o letsencrypt realize a validação do seu dominio e consiga gerar os seus certificados SSL_);

5. **EMAIL**: Essa variável é utilizada exclusivamente para que o letsencrypt possa te notificar sobre a geração dos seus certificados SSL bem como quando a data de expiração estiver próxima.

6. **DOMAIN**: Seu nome de domínio registrado sem nenhum prefixo (subdominio), por exemplo: `meuapp.com.br`. Essa informação será utilizada em varios momentos durante o deploy, desde a construção do RecordSet registrado ao seu HostedZone até a criação de scripts no nginx para o gerenciamento adequado do proxy reverso;

7. **SUBDOMAIN**: O subdomínio que irá responder para a sua aplicação, é para esse subdominio que o certificado SSL será gerado. Deve ser definido apenas o nome do subdominio, a IaC resolverá o restante, por exemplo.: `app` ou `www`;

8. **APP_NAME**: Uma Alias Name para o seu projeto, deve possuir todos os caracteres em minúsculos, sem espaçoes ou caracteres especiais, preferencialmente apenas caracteres alfanumericos, por exemplo: `meuapp`. Essa informação será utilizada para nomear todos os recursos gerados através da IaC, garantindo que esses recursos possuam nomes únicos na sua infraestrutura de cloud.

#### 1.3 - Ambientes da sua Aplicação

O arquivo `.gitlab-ci.yml` está configurado para executar o pipeline apenas em ambiente de **staging** e **production**. Para que seja evitado problemas de interpretação entre os membros da sua equipe, eu recomendo fortemente que os nomes das suas branches sigam os mesmos nomes dos ambientes, com isso, o CI evita de realizar mapeamentos (**de:para**) entre os seus nomes de ambiente e branches e os membros da sua equipe conseguem enchergar o co-relacionamento **env - branch** de forma mais intuitiva;

Por convenção, eu recomendo que sejam criadas 3 branchs principais, **develop**, **staging** e **production**, onde develop deve ser sua branch default, responsável por centralizar o código das branches de todos os membros do time, já staging e production são responsáveis por receber o merge de develop quando um novo deploy estiver pronto para ser executado.

### 2 - Explicando o arquivo .gitlab-ci.yml

O arquivo é o primeiro a ser executado quando a pipeline de deploy é iniciada (quando é feito um merge do código para a branch de staging ou production), ele é responsável por instalar as dependencias necessárias para executar o serverless e os comandos de cli da AWS. Esse projeto tem como objetivo ser o mais simples possível dentro de toda sua complexidade, portanto foi definido apenas um stage no arquivo.

O stage de deploy possui 3 responsabilidades, são elas:

1. Executar o serverless para que todos os recursos necessário da aplicação sejam criados dentro da sua infraestrutura AWS;

2. Compactar e armazenar o código da aplicação (pasta `web`) dentro de um bucket no AWS S3, previamente criado através do serverless;

3. Realizar o deploy dessa aplicação armazenada na no AWS S3 dentro do ElasticBeanstalk, também préviamente criado pelo serverless;


### 3 - Explicando o arquivo serverless.yml

Esse arquivo é executado durante o processo de CI e utiliza o serverless framework para provisionar os recursos na AWS via CloudFormation.

Abaixo eu descrevo todos os recursos provisionados bem como o objetivo de cada um:

1. **BucketCerts**: Bucket no S3 para armazenar o estado do letsencrypt (pastas e arquivos presentes na máquina do nginx) que é gerenciado pelo certbot. Esse recurso é necessário para que case a maquina do nginx seja recriada, todos os arquivos referentes ao certificado sejam recuperados evitando que o certbot crie um certificado totalmente novo.
2. **Bucket**: Bucket no S3 para armazenar as versões de deploy da aplicação. Toda vez que um novo deploy é realizado, a pasta web é compactada e enviada para este bucket, permitindo que uma nova versão no elastic beanstalk seja criada.
3. **BeanstalkApplication**: A Aplicação no Elastic Beanstalk própriamente dita.
4. **BeanstalkEnv**: O ambiente em que a aplicação será criada, mudando de acordo com os buckets de staging e production.
5. **ElasticBeanstalkInstanceProfile**: Um novo perfil de instância para que roles possam ser anexadas as maquinas gerenciadas pelo elastic beanstalk.
6. **ElasticBeanstalkEc2AssumeRole**: Uma role customizada permitindo que as maquinas gerenciadas pelo elastic beanstalk possam realizar upload e download de arquivos no bucket de certificados préviamente provisionado.
7. **PrimaryRoute53Record**: Deve ser criado um registro no HostedZone do Route53 com o domínio para qual o certificado será gerado, esse recurso é importante para que o apontamento esteja disponível antes do deploy da aplicação ser realizado, permitindo que no momento de startup da aplicação, o certbot consiga verificar se o domínio para qual o certificado será gerado é válido.

### Docker 

```sh
docker system prune -a
```

```sh
docker restart {container_id}
```

```sh
docker logs nginx
```

```sh
docker exec -it nginx /bin/bash 
```


// sempre limpar o cache do docker para evitar problemas de configuração, principalmente se esta fazendo muitos testes.

// utilizar find ./etc/letsencrypt -type l para verificar links simbolicos no letsencypt