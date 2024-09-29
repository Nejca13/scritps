#!/bin/bash

# Colores
RED='\033[1;38;2;237;135;150m'    # Rojo pastel (#ed8796) en negrita
GREEN='\033[1;38;2;166;218;149m'  # Verde pastel (#a6da95) en negrita
YELLOW='\033[1;38;2;238;212;159m' # Amarillo pastel (#eed49f) en negrita
BLUE='\033[1;34m'                 # Azul en negrita
NC='\033[0m'                      # No Color

spinner() {
  local pid=$1
  local delay=0.75
  local spin='-\|/'

  while ps -p $pid > /dev/null; do
    local temp=${spin#?}
    printf "${BLUE} [%c]  " "$spin"
    spin=$temp${spin%"$temp"}
    sleep $delay
    printf "\r"
  done
  printf "    \r"  # Limpia la línea
}

# Solicitar el nombre del proyecto
echo -e "${YELLOW}Ingrese el nombre del proyecto: ${NC}"
read -r PROJECT_NAME

# Verificar si Node.js está instalado
if ! [ -x "$(command -v node)" ]; then
  echo -e "${RED}Error: Node.js no está instalado.${NC}" >&2
  echo -e "${YELLOW}¿Desea instalar Node.js usando NVM? (sí/no): ${NC}"
  read INSTALL_NODE

  if [[ $INSTALL_NODE == "sí" || $INSTALL_NODE == "s" ]]; then
    echo -e "${YELLOW}Instalando NVM...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # Esto carga nvm
    echo -e "${GREEN}NVM instalado. Ahora instalando Node.js...${NC}"
    nvm install node
    nvm use node
  else
    echo -e "${RED}Node.js no está instalado y no se realizará la instalación.${NC}" >&2
    exit 1
  fi
else
  echo -e "${GREEN}Node.js está instalado.${NC}"
fi

# Verificar si pnpm está instalado
if ! [ -x "$(command -v pnpm)" ]; then
  echo -e "${RED}Error: pnpm no está instalado. Por favor, instala pnpm para continuar.${NC}" >&2
  echo -e "${YELLOW}¿Desea instalar pnpm usando NPM? (sí/no): ${NC}"
  read INSTALL_PNPM

  if [[ $INSTALL_PNPM == "sí" || $INSTALL_PNPM == "s" ]]; then
    npm install -g pnpm
    echo -e "${GREEN}pnpm instalado.${NC}"
  else 
    echo -e "${RED}pnpm no está instalado y no se realizará la instalación.${NC}" >&2
    exit 1  
  fi
else
  echo -e "${GREEN}pnpm está instalado.${NC}"
  
fi

# Verificar si Python está instalado
if ! [ -x "$(command -v python3)" ]; then
  echo -e "${RED}Error: Python3 no está instalado.${NC}" >&2
  exit 1
else
  echo -e "${GREEN}Python3 está instalado.${NC}"
fi

# Verificar si MongoDB está instalado
if ! [ -x "$(command -v mongod)" ]; then
  echo -e "${RED}Error: MongoDB no está instalado.${NC}" >&2
  exit 1
else
  echo -e "${GREEN}MongoDB está instalado.${NC}"
fi

# Iniciar proyecto Next.js con el nombre especificado usando pnpm
pnpm create next-app $PROJECT_NAME
cd $PROJECT_NAME
echo -e "${GREEN}Proyecto Next.js creado y se ha navegado al directorio $PROJECT_NAME.${NC}"

# Configurar ESLint y Prettier con pnpm
pnpm add -D eslint prettier concurrently
echo -e "${GREEN}Configuraciones predeterminadas de ESLint y Prettier aplicadas.${NC}"

# Crear carpeta para FastAPI
mkdir -p src/app/api
cd src/app/api
echo -e "${GREEN}Carpeta para FastAPI creada.${NC}"

# Crear archivo requirements.txt
touch requirements.txt
echo -e "${GREEN}Archivo requirements.txt creado.${NC}"

# Configurar entorno virtual de Python
python3 -m venv env
source env/bin/activate
echo -e "${GREEN}Entorno virtual de Python activado.${NC}"
echo -e "\n"
echo -e "${YELLOW}Instalando dependencias de Python...${NC}"
# Instalar FastAPI y Uvicorn

{
  pip install fastapi uvicorn beanie pymongo python-dotenv python-multipart passlib pyjwt python-jose email-validator > /dev/null 2>&1
} &
  pid=$!
  spinner $pid
  wait $pid
echo -e "${GREEN}Dependencias de Python instaladas [fastapi, uvicorn, beani, pymongo, python-dotenv, python-multipart, passlib, pyjwt, python-jose].${NC}"

# Preguntar si se quieren instalar dependencias adicionales
echo -e "${YELLOW}¿Desea instalar dependencias adicionales para FastAPI? (sí/no): ${NC}"
read INSTALL_EXTRA_DEPS

if [[ $INSTALL_EXTRA_DEPS == "sí" || $INSTALL_EXTRA_DEPS == "s" ]]; then
  echo -e "${YELLOW}Ingrese las dependencias adicionales separadas por espacio: ${NC}"
  read EXTRA_DEPS
  {
    pip install $EXTRA_DEPS > /dev/null 2>&1
  } &
    pid=$!
    spinner $pid
    wait $pid

  echo $EXTRA_DEPS >> requirements.txt
  echo -e "${GREEN}Dependencias adicionales instaladas: $EXTRA_DEPS.${NC}"
else
  echo -e "${YELLOW}No se instalaron dependencias adicionales.${NC}"
fi

echo -e "${GREEN}Instalación de dependencias de Python completada.${NC}"
echo -e "\n"

# Crear archivo básico de FastAPI
cat > main.py << EOL
from fastapi import FastAPI
from .models.usuarios import init_db
from .routers import usuarios  # Importar el router de usuarios
from .auth import auth

app = FastAPI()

@app.on_event("startup")
async def on_startup():
    await init_db()  # Inicializar la base de datos Beanie

app.include_router(usuarios.router, prefix="/usuarios", tags=["Usuarios"])  # Incluir el router de usuarios

app.include_router(auth.router, prefix="/auth", tags=["Auth"])

EOL

echo -e "${GREEN}Archivo básico de FastAPI creado.${NC}"

# Crear la carpeta auth en la ruta src/app/api
mkdir -p auth

# Crear el archivo auth.py con el contenido proporcionado
cat > auth/auth.py << EOL
from fastapi import APIRouter, HTTPException, Depends, Form
from pydantic import BaseModel, EmailStr, constr
from pymongo import MongoClient
from passlib.context import CryptContext
import jwt  
from datetime import datetime, timedelta
import os

client = MongoClient(os.getenv("MONGO_URI"))
db = client.festclub
usuarios_collection = db.usuarios

router = APIRouter(prefix="/auth", tags=["Auth"])

SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Modelo para la solicitud de login
class LoginRequest(BaseModel):
    email: EmailStr
    password: constr(min_length=8)  # Contraseña debe tener mínimo 8 caracteres

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: timedelta = timedelta(minutes=120)):
    to_encode = data.copy()
    expire = datetime.utcnow() + expires_delta
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

@router.post("/login")
async def login(request: LoginRequest):
    usuario = usuarios_collection.find_one({"email": request.email})

    if usuario and verify_password(request.password, usuario["password"]):
        usuario["_id"] = str(usuario["_id"])
        token = create_access_token(data={"sub": usuario["_id"]})
        return {"access_token": token, "token_type": "bearer", **{k: v for k, v in usuario.items() if k != "password"}}
    else:
        raise HTTPException(status_code=400, detail="Email o Password inválido")
EOL

echo -e "${GREEN}El archivo auth.py ha sido creado en src/app/api/auth con éxito.${NC}"

mkdir -p models routers


echo -e "${GREEN}Directorios /models y /routers creados.${NC}"

# Crear el archivo de modelo para usuarios - usuario.py

cat > models/usuarios.py << EOL
from beanie import Document, init_beanie
from pydantic import EmailStr, BaseModel
from motor.motor_asyncio import AsyncIOMotorClient
from passlib.context import CryptContext
import os

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class Usuario(BaseModel):
    email: EmailStr
    password: str

class UsuarioDocument(Document, Usuario):
    class Settings:
        collection = "usuarios"

    def hash_password(self):
        self.password = pwd_context.hash(self.password)

async def init_db():
    project_name = "$PROJECT_NAME"
    client = AsyncIOMotorClient(os.getenv("mongodb://localhost:27017"))
    await init_beanie(database=client[project_name], document_models=[UsuarioDocument])
EOL

echo -e "${GREEN}Archivo de modelo usuario.py creado.${NC}"

# Crear el archivo de rutas para usuarios - usuarios.py

cat > routers/usuarios.py << EOL
from fastapi import APIRouter, HTTPException
from ..models.usuarios import UsuarioDocument

router = APIRouter(prefix="/usuarios", tags=["Usuarios"])

@router.post("/", response_model=UsuarioDocument)
async def create_usuario(usuario: UsuarioDocument):
    usuario.hash_password()  # Hashear la contraseña
    existing_user = await UsuarioDocument.find_one(UsuarioDocument.email == usuario.email)
    if existing_user:
        raise HTTPException(status_code=400, detail="El correo ya está en uso")
    
    await usuario.insert()
    return usuario
EOL

# Crear el archivo start_fastapi.sh para levantar FastAPI
cat > ../../../start_fastapi.sh << EOL
#!/bin/bash

source src/app/api/env/bin/activate

pip install -r src/app/api/requirements.txt

export PYTHONPATH=\$(pwd)

uvicorn src.app.api.main:app --host 0.0.0.0 --port 8000 --reload
EOL

chmod +x ../../../start_fastapi.sh
echo -e "${GREEN}Script start_fastapi.sh creado y marcado como ejecutable.${NC}"

# Volver al directorio raíz del proyecto
cd ../../../

# Crear el archivo next.config.mjs
cat > next.config.mjs << EOL
/** @type {import('next').NextConfig} */
const nextConfig = {
  rewrites: async () => {
    return [
      {
        source: '/api/:path*',
        destination: 'http://localhost:8000/:path*/',
      },
    ]
  },
}

export default nextConfig
EOL

echo -e "${GREEN}Archivo next.config.mjs creado.${NC}"

# Modificar el package.json con los scripts requeridos
cat > package.json << EOL
{
  "name": "$PROJECT_NAME",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "fastapi-dev": "./start_fastapi.sh",
    "next-dev": "next dev",
    "dev": "concurrently \"pnpm run next-dev\" \"pnpm run fastapi-dev\"",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "prod": "concurrently \"pnpm run start\" \"pnpm run fastapi-dev\""
  },
  "dependencies": {
    "next": "latest",
    "react": "latest",
    "react-dom": "latest"
  },
  "devDependencies": {
    "eslint": "latest",
    "prettier": "latest",
    "concurrently": "latest"
  }
}
EOL

echo -e "${GREEN}Scripts agregados a package.json.${NC}"
echo -e "\n"
echo -e "${GREEN}¡Proyecto $PROJECT_NAME configurado exitosamente!${NC}"
echo -e "\n"
echo -e "${YELLOW}Navega al directorio de tu proyecto con 'cd $PROJECT_NAME'${NC}"
echo -e "${GREEN}¡Ejecuta 'pnpm run dev' para iniciar el proyecto.${NC}"
echo -e "\n"
# Fin del script y pasamos los links del front y el back
echo -e "${GREEN}El frontend esta disponible en ${BLUE}http://localhost:3000${NC}"
echo -e "${GREEN}El backend esta disponible en ${BLUE}http://localhost:8000${NC}"

# Cambiar al directorio del proyecto
cd $PROJECT_NAME  # Asegúrate de que el directorio existe

# Ejecutar el comando pnpm run dev en segundo plano
pnpm run dev &

# Mostrar opciones al usuario
function show_options() {
  echo -e "\n${YELLOW}Opciones disponibles:"
  echo -e "${BLUE}  [O] - Abrir el editor de código${NC}"
  echo -e "${BLUE}  [W] - Abrir el navegador en el frontend${NC}"
  echo -e "${BLUE}  [Q] - Salir del script${NC}"
  echo -e "${GREEN}Presiona la tecla correspondiente..."
}

# Mostrar las opciones al usuario
show_options

# Capturar la entrada del usuario
while true; do
    read -n 1 -s key  # Leer una sola tecla sin esperar Enter
    case $key in
        o|O)
            echo -e "\nAbriendo el editor de código..."
            code . &  # Esto abrirá el directorio en el editor de código por defecto
            ;;
        w|W)
            echo -e "\nAbriendo el navegador..."
            xdg-open "http://localhost:3000" &  # Cambia esto si tu URL de frontend es diferente
            xdg-open "http://localhost:8000" &  # Cambia esto si tu URL de backend es diferente
            ;;
        q|Q)
            echo -e "\nSaliendo..."
            break  # Salir del bucle si se presiona 'Q'
            ;;
        *)
            echo -e "\nTecla no válida. Presiona [O], [W] o [Q]."  # Mensaje para tecla no válida
            ;;
    esac
    show_options
done

